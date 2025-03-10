(*
 * Copyright (c) 2015, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the "hack" directory of this source tree.
 *
 *)

(*
 * The server monitor is the parent process for a server. It
 * listens to a socket for client connections and passes the connections
 * to the server and serves the following objectives:
 *
   * 1) Readily accepts client connections
   * 2) Confirms a Build ID match (killing itself and the server quickly
   *    on mismatch)
   * 3) Hands the client connection to the daemon server
   * 4) Tracks when the server process crashes or OOMs and echos
   *    its fate to the next client.
 *)

open Hh_prelude
open ServerProcess
open ServerMonitorUtils

let log s ~tracker =
  Hh_logger.log ("[%s] " ^^ s) (Connection_tracker.log_id tracker)

(** This module is to help using Unix "sendmsg" to handoff the client FD
to the server. It's not entirely clear whether it's safe for us in the
monitor to close the FD immediately after calling sendmsg, or whether
we must wait until the server has actually received the FD upon recvmsg.

We got reports from MacOs users that if the monitor closed the FD before
the server had finished recvmsg, then the kernel thinks it was the last open
descriptor for the pipe, and actually closes it; the server subsequently
does recvmsg and reads on the FD and gets an EOF (even though it can write
on the FD and succeed instead of getting EPIPE); the server subsequently
closes its FD and a subsequent "select" by the client blocks forever.

This module embodies three possible strategies, controlled by the hh.conf
flag monitor_fd_close_delay:
* Fd_close_immediate (monitor_fd_close_delay=0) is the traditional behavior of
hack; it closes the FD immediately after calling sendmsg
* Fd_close_after_time (monitor_fd_close_delay>0) is the behavior we implemented
on MacOs since 2018, where monitor waits for the specified time delay, in seconds,
after calling sendmsg before it closes the FD
* Fd_close_upon_receipt (monitor_fd_close_delay=-1) is new behavior in 2021, where
the monitor waits to close the FD until after the server has read it.

We detect that the server has read it by having the server write the highest
handoff number it has received to a "server_receipt_to_monitor_file", and the
monitor polls this file to determine which handoff FD can be closed. It might
be that the server receives two FD handoffs in quick succession, and the monitor
only polls the file after the second, so the monitor treats the file as a
"high water mark" and knows that it can close the specified FD plus all earlier ones.

We did this protocol with a file because there aren't alternatives. If we tried
instead to have the server send receipt over the monitor/server pipe, then it
would deadlock if the monitor was also trying to handoff a subsequent FD.
If we tried instead to have the server send receipt over the client/server pipe,
then both monitor and client would be racing to see who receives that receipt first. *)
module Sent_fds_collector = struct
  (** [sequence_number] is a monotonically increasing integer to identify which
  handoff message has been sent from monitor to server. The first sequence
  number is number 1. *)
  let sequence_number : int ref = ref 0

  let get_and_increment_sequence_number () : int =
    sequence_number := !sequence_number + 1;
    !sequence_number

  type fd_close_time =
    | Fd_close_immediate
    | Fd_close_after_time of float
    | Fd_close_upon_receipt

  type handed_off_fd_to_close = {
    fd_close_time: fd_close_time;
    tracker: Connection_tracker.t;
    fd: Unix.file_descr;
    m2s_sequence_number: int;
  }

  let handed_off_fds_to_close : handed_off_fd_to_close list ref = ref []

  let cleanup_fd ~tracker ~fd_close_time ~m2s_sequence_number fd =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    match fd_close_time with
    | Fd_close_immediate ->
      log "closing client fd immediately after handoff" ~tracker;
      Unix.close fd
    | _ ->
      handed_off_fds_to_close :=
        { fd_close_time; tracker; fd; m2s_sequence_number }
        :: !handed_off_fds_to_close

  let collect_garbage ~sequence_receipt_high_water_mark =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let t_now = Unix.gettimeofday () in
    let (ready, notready) =
      List.partition_tf
        !handed_off_fds_to_close
        (fun { fd_close_time; tracker; m2s_sequence_number; _ } ->
          match fd_close_time with
          | Fd_close_immediate ->
            log
              "closing client FD#%d, though should have been immediate"
              ~tracker
              m2s_sequence_number;
            true
          | Fd_close_after_time t when t <= t_now ->
            log "closing client FD#%d, after delay" ~tracker m2s_sequence_number;
            true
          | Fd_close_upon_receipt
            when m2s_sequence_number <= sequence_receipt_high_water_mark ->
            log
              "closing client FD#%d upon receipt of #%d"
              ~tracker
              m2s_sequence_number
              sequence_receipt_high_water_mark;
            true
          | _ -> false)
    in
    List.iter ready ~f:(fun { fd; _ } -> Unix.close fd);
    handed_off_fds_to_close := notready;
    ()
end

exception Malformed_build_id of string

exception Send_fd_failure of int

module Make_monitor
    (SC : ServerMonitorUtils.Server_config)
    (Informant : Informant_sig.S) =
struct
  type env = {
    informant: Informant.t;
    server: ServerProcess.server_process;
    server_start_options: SC.server_start_options;
    (* How many times have we tried to relaunch it? *)
    retries: int;
    sql_retries: int;
    watchman_retries: int;
    max_purgatory_clients: int;
    (* Version of this running server, as specified in the config file. *)
    current_version: Config_file.version;
    (* After sending a Server_not_alive_dormant during Prehandoff,
     * clients are put here waiting for a server to come alive, at
     * which point they get pushed through the rest of prehandoff and
     * then sent to the living server.
     *
     * String is the server name it wants to connect to. *)
    purgatory_clients:
      (Connection_tracker.t * MonitorRpc.handoff_options * Unix.file_descr)
      Queue.t;
    (* Whether to ignore hh version mismatches *)
    ignore_hh_version: bool;
    (* After we handoff FD to server, how many seconds to wait before closing?
     * 0 means "close immediately"
     * -1 means "wait for server receipt" *)
    monitor_fd_close_delay: int;
    (* This flag controls whether ClientConnect responds to monitor backpressure,
    and ServerMonitor responds to server backpressure *)
    monitor_backpressure: bool;
  }

  type t = env * ServerMonitorUtils.monitor_config * Unix.file_descr

  let msg_to_channel fd msg =
    (* This FD will be passed to a server process, so avoid using Ocaml's
     * channels which have built-in buffering. Even though we are only writing
     * to the FD here, it seems using Ocaml's channels also causes read
     * buffering to happen here, so the server process doesn't get what was
     * meant for it. *)
    Marshal_tools.to_fd_with_preamble fd msg |> ignore

  let setup_handler_for_signals handler signals =
    List.iter signals (fun signal ->
        Sys_utils.set_signal signal (Sys.Signal_handle handler))

  let setup_autokill_server_on_exit process =
    try
      setup_handler_for_signals
        begin
          fun _ ->
          Hh_logger.log "Got an exit signal. Killing server and exiting.";
          SC.kill_server process;
          Exit.exit Exit_status.Interrupted
        end
        [Sys.sigint; Sys.sigquit; Sys.sigterm; Sys.sighup]
    with _ -> Hh_logger.log "Failed to set signal handler"

  let sleep_and_check socket =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let (ready_socket_l, _, _) = Unix.select [socket] [] [] 1.0 in
    not (List.is_empty ready_socket_l)

  let start_server ?target_saved_state ~informant_managed options exit_status =
    let server_process =
      SC.start_server
        ?target_saved_state
        ~prior_exit_status:exit_status
        ~informant_managed
        options
    in
    setup_autokill_server_on_exit server_process;
    Alive server_process

  let maybe_start_first_server options informant : ServerProcess.server_process
      =
    if Informant.should_start_first_server informant then (
      Hh_logger.log "Starting first server";
      HackEventLogger.starting_first_server ();
      start_server
        ~informant_managed:(Informant.is_managing informant)
        options
        None
    ) else (
      Hh_logger.log
        ( "Not starting first server. "
        ^^ "Starting will be triggered by informant later." );
      Not_yet_started
    )

  let kill_server_with_check = function
    | Alive server -> SC.kill_server server
    | _ -> ()

  let wait_for_server_exit_with_check server kill_signal_time =
    match server with
    | Alive server -> SC.wait_for_server_exit server kill_signal_time
    | _ -> ()

  let kill_server_and_wait_for_exit env =
    kill_server_with_check env.server;
    let kill_signal_time = Unix.gettimeofday () in
    wait_for_server_exit_with_check env.server kill_signal_time

  (* Reads current hhconfig contents from disk and returns true if the
   * version specified in there matches our currently running version. *)
  let is_config_version_matching env =
    let filename =
      Relative_path.from_root
        ~suffix:Config_file.file_path_relative_to_repo_root
    in
    let (_hash, config) =
      Config_file.parse_hhconfig
        ~silent:true
        (Relative_path.to_absolute filename)
    in
    let new_version =
      Config_file.parse_version (SMap.find_opt "version" config)
    in
    0 = Config_file.compare_versions env.current_version new_version

  (* Actually starts a new server. *)
  let start_new_server ?target_saved_state env exit_status =
    let informant_managed = Informant.is_managing env.informant in
    let new_server =
      start_server
        ?target_saved_state
        ~informant_managed
        env.server_start_options
        exit_status
    in
    { env with server = new_server; retries = env.retries + 1 }

  (* Kill the server (if it's running) and restart it - maybe. Obeying the rules
   * of state transitions. See docs on the ServerProcess.server_process ADT for
   * state transitions. *)
  let kill_and_maybe_restart_server ?target_saved_state env exit_status =
    (* Ideally, all restarts should be triggered by Changed_merge_base notification
     * which generate target mini state. There are other kind of restarts too, mostly
     * related to server crashing - if we just restart and keep going, we risk
     * Changed_merge_base eventually arriving and restarting the already started server
     * for no reason. Re-issuing merge base query here should bring the Monitor and Server
     * understanding of current revision to be the same *)
    if Option.is_none target_saved_state then Informant.reinit env.informant;
    kill_server_and_wait_for_exit env;
    let version_matches = is_config_version_matching env in
    if SC.is_saved_state_precomputed env.server_start_options then begin
      let reason =
        "Not restarting server as requested, server was launched using a "
        ^ "precomputed saved-state. Exiting monitor"
      in
      Hh_logger.log "%s" reason;
      HackEventLogger.refuse_to_restart_server
        ~reason
        ~server_state:(ServerProcess.show_server_process env.server)
        ~version_matches;
      Exit.exit Exit_status.Not_restarting_server_with_precomputed_saved_state
    end;
    match (env.server, version_matches) with
    | (Died_config_changed, _) ->
      (* Now we can start a new instance safely.
       * See diagram on ServerProcess.server_process docs. *)
      start_new_server ?target_saved_state env exit_status
    | (Not_yet_started, false)
    | (Alive _, false)
    | (Died_unexpectedly _, false) ->
      (* Can't start server instance. State goes to Died_config_changed
       * See diagram on ServerProcess.server_process docs. *)
      Hh_logger.log
        "Avoiding starting a new server because version in config no longer matches.";
      { env with server = Died_config_changed }
    | (Not_yet_started, true)
    | (Alive _, true)
    | (Died_unexpectedly _, true) ->
      (* Start new server instance because config matches.
       * See diagram on ServerProcess.server_process docs. *)
      start_new_server ?target_saved_state env exit_status

  let read_version fd =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let s : string = Marshal_tools.from_fd_with_preamble fd in
    let newline_byte = Bytes.create 1 in
    let _ = Unix.read fd newline_byte 0 1 in
    if not (String.equal (Bytes.to_string newline_byte) "\n") then
      raise (Malformed_build_id "missing newline after version");
    (* Newer clients send version in a json object.
    Older clients sent just a client_version string *)
    if String_utils.string_starts_with s "{" then
      try Hh_json.json_of_string s
      with e -> raise (Malformed_build_id (Exn.to_string e))
    else
      Hh_json.JSON_Object [("client_version", Hh_json.JSON_String s)]

  let hand_off_client_connection ~tracker env server_fd client_fd =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let m2s_sequence_number =
      Sent_fds_collector.get_and_increment_sequence_number ()
    in
    let msg = MonitorRpc.{ m2s_tracker = tracker; m2s_sequence_number } in
    msg_to_channel server_fd msg;
    log "Handed off tracker #%d to server" ~tracker m2s_sequence_number;
    let status = Libancillary.ancil_send_fd server_fd client_fd in
    if status = 0 then begin
      log "Handed off FD#%d to server" ~tracker m2s_sequence_number;
      let fd_close_time =
        if env.monitor_fd_close_delay = 0 then
          (* delay 0 means "close immediately" *)
          Sent_fds_collector.Fd_close_immediate
        else if env.monitor_fd_close_delay = -1 then
          (* delay -1 means "close upon read receipt" *)
          Sent_fds_collector.Fd_close_upon_receipt
        else
          (* delay >=1 means "close after this time" *)
          Sent_fds_collector.Fd_close_after_time
            (Unix.gettimeofday () +. float_of_int env.monitor_fd_close_delay)
      in
      Sent_fds_collector.cleanup_fd
        ~tracker
        ~fd_close_time
        ~m2s_sequence_number
        client_fd
    end else begin
      log "Failed to handoff FD#%d to server." ~tracker m2s_sequence_number;
      raise (Send_fd_failure status)
    end

  (** Sends the client connection FD to the server process then closes the FD.
  Backpressure: We have a timeout of 30s here to wait for the server to accept
  the handoff. That timeout will be exceeded if monitor->server pipe has filled
  up from previous requests and the server's current work item is costly. In this
  case we'll give up on the handoff, and hh_client will fail with Server_hung_up_should_retry,
  and find_hh.sh will retry with exponential backoff.
  During the 30s while we're blocked here, if there are lots of other clients trying
  to connect to the monitor and the monitor's incoming queue is full, they'll time
  out trying to open a connection to the monitor. Their response is to back off,
  with exponentially longer timeouts they're willing to wait for the monitor to become
  available. In this way the queue of clients is stored in the unix process list.
  Why did we pick 30s? It's arbitrary. If we decreased then, if there are lots of clients,
  they'll do more work while they needlessly cycle. If we increased up to infinite
  then I worry that a failure for other reasons might look like a hang.
  This 30s must be comfortably shorter than the 60s delay in ClientConnect.connect, since
  if not then by the time we in the monitor timeout we'll find that every single item
  in our incoming queue is already stale! *)
  let hand_off_client_connection_wrapper ~tracker env server_fd client_fd =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let timeout =
      if env.monitor_backpressure then
        30.0
      else
        4.0
    in
    let to_finally_close = ref (Some client_fd) in
    Utils.try_finally
      ~f:(fun () ->
        let (_, ready_l, _) = Unix.select [] [server_fd] [] timeout in
        if List.is_empty ready_l then
          log
            ~tracker
            "Handoff FD timed out (%.1fs): server's current iteration is taking longer than that, and its incoming pipe is full"
            timeout
        else
          try
            hand_off_client_connection ~tracker env server_fd client_fd;
            to_finally_close := None
          with
          | Unix.Unix_error (Unix.EPIPE, _, _) ->
            log
              ~tracker
              "Handoff FD failed: server has closed its end of pipe (EPIPE), maybe due to large rebase or incompatible .hhconfig change or crash"
          | exn ->
            let e = Exception.wrap exn in
            log
              ~tracker
              "Handoff FD failed unexpectedly - %s"
              (Exception.to_string e);
            HackEventLogger.send_fd_failure e)
      ~finally:(fun () ->
        match !to_finally_close with
        | None -> ()
        | Some client_fd ->
          log
            ~tracker
            "Sending Monitor_failed_to_handoff to client, and closing FD";
          msg_to_channel client_fd ServerCommandTypes.Monitor_failed_to_handoff;
          Unix.close client_fd)

  (* Does not return. *)
  let client_out_of_date_ client_fd mismatch_info =
    msg_to_channel client_fd (Build_id_mismatch_ex mismatch_info);
    HackEventLogger.out_of_date ()

  (* Kills servers, sends build ID mismatch message to client, and exits.
   *
   * Does not return. Exits after waiting for server processes to exit. So
   * the client can wait for socket closure as indication that both the monitor
   * and server have exited.
   *)
  let client_out_of_date env client_fd mismatch_info =
    Hh_logger.log "Client out of date. Killing server.";
    kill_server_with_check env.server;
    let kill_signal_time = Unix.gettimeofday () in
    (* If we detect out of date client, should always kill server and exit
     * monitor, even if messaging to channel or event logger fails. *)
    (try client_out_of_date_ client_fd mismatch_info
     with e ->
       Hh_logger.log
         "Handling client_out_of_date threw with: %s"
         (Exn.to_string e));
    wait_for_server_exit_with_check env.server kill_signal_time;
    Exit.exit Exit_status.Build_id_mismatch

  (** Send (possibly empty) sequences of messages before handing off to
      server. *)
  let rec client_prehandoff
      ~tracker ~is_purgatory_client env handoff_options client_fd =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let module PH = Prehandoff in
    match env.server with
    | Alive server ->
      let server_fd =
        snd
        @@ List.find_exn server.out_fds ~f:(fun x ->
               String.equal (fst x) handoff_options.MonitorRpc.pipe_name)
      in
      let t_ready = Unix.gettimeofday () in
      let tracker =
        Connection_tracker.(track tracker ~key:Monitor_ready ~time:t_ready)
      in
      (* TODO: Send this to client so it is visible. *)
      log
        "Got %s request for typechecker. Prior request %.1f seconds ago"
        ~tracker
        handoff_options.MonitorRpc.pipe_name
        (t_ready -. !(server.last_request_handoff));
      msg_to_channel client_fd (PH.Sentinel server.server_specific_files);
      let tracker =
        Connection_tracker.(track tracker ~key:Monitor_sent_ack_to_client)
      in
      hand_off_client_connection_wrapper ~tracker env server_fd client_fd;
      server.last_request_handoff := Unix.time ();
      { env with server = Alive server }
    | Died_unexpectedly (status, was_oom) ->
      (* Server has died; notify the client *)
      msg_to_channel client_fd (PH.Server_died { PH.status; PH.was_oom });

      (* Next client to connect starts a new server. *)
      Exit.exit Exit_status.No_error
    | Died_config_changed ->
      if not is_purgatory_client then (
        let env = kill_and_maybe_restart_server env None in
        (* Assert that the restart succeeded, and then push prehandoff through again. *)
        match env.server with
        | Alive _ ->
          (* Server restarted. We want to re-run prehandoff, which will
           * actually do the prehandoff this time. *)
          client_prehandoff
            ~tracker
            ~is_purgatory_client
            env
            handoff_options
            client_fd
        | Died_unexpectedly _
        | Died_config_changed
        | Not_yet_started ->
          Hh_logger.log
            ( "Unreachable state. Server should be alive after trying a restart"
            ^^ " from Died_config_changed state" );
          failwith
            "Failed starting server transitioning off Died_config_changed state"
      ) else (
        msg_to_channel client_fd PH.Server_died_config_change;
        env
      )
    | Not_yet_started ->
      let env =
        if handoff_options.MonitorRpc.force_dormant_start then (
          msg_to_channel
            client_fd
            (PH.Server_not_alive_dormant
               "Warning - starting a server by force-dormant-start option...");
          kill_and_maybe_restart_server env None
        ) else (
          msg_to_channel
            client_fd
            (PH.Server_not_alive_dormant
               "Server killed by informant. Waiting for next server...");
          env
        )
      in
      if Queue.length env.purgatory_clients >= env.max_purgatory_clients then
        let () =
          msg_to_channel client_fd PH.Server_dormant_connections_limit_reached
        in
        env
      else
        let () =
          Queue.enqueue
            env.purgatory_clients
            (tracker, handoff_options, client_fd)
        in
        env

  let handle_monitor_rpc env client_fd =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let cmd : MonitorRpc.command =
      Marshal_tools.from_fd_with_preamble client_fd
    in
    match cmd with
    | MonitorRpc.HANDOFF_TO_SERVER (tracker, handoff_options) ->
      let tracker =
        Connection_tracker.(track tracker ~key:Monitor_received_handoff)
      in
      client_prehandoff
        ~tracker
        ~is_purgatory_client:false
        env
        handoff_options
        client_fd
    | MonitorRpc.SHUT_DOWN tracker ->
      log "Got shutdown RPC. Shutting down." ~tracker;
      let kill_signal_time = Unix.gettimeofday () in
      kill_server_with_check env.server;
      wait_for_server_exit_with_check env.server kill_signal_time;
      Exit.exit Exit_status.No_error

  let ack_and_handoff_client env client_fd =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    try
      let start_time = Unix.gettimeofday () in
      let json = read_version client_fd in
      let client_version =
        match Hh_json_helpers.Jget.string_opt (Some json) "client_version" with
        | Some client_version -> client_version
        | None -> raise (Malformed_build_id "Missing client_version")
      in
      let tracker_id =
        Hh_json_helpers.Jget.string_opt (Some json) "tracker_id"
        |> Option.value ~default:"t#?"
      in
      Hh_logger.log
        "[%s] read_version: got version %s, started at %s"
        tracker_id
        (Hh_json.json_to_string json)
        (start_time |> Utils.timestring);
      if
        (not env.ignore_hh_version)
        && not (String.equal client_version Build_id.build_revision)
      then (
        Hh_logger.log
          "New client version is %s, while currently running server version is %s"
          client_version
          Build_id.build_revision;
        client_out_of_date env client_fd ServerMonitorUtils.current_build_info
      ) else (
        Hh_logger.log "[%s] sending Connection_ok..." tracker_id;
        msg_to_channel client_fd Connection_ok;
        handle_monitor_rpc env client_fd
      )
    with Malformed_build_id _ as exn ->
      let e = Exception.wrap exn in
      HackEventLogger.malformed_build_id e;
      Hh_logger.log "Malformed Build ID - %s" (Exception.to_string e);
      Exception.reraise e

  let push_purgatory_clients env =
    (* We create a queue and transfer all the purgatory clients to it before
     * processing to avoid repeatedly retrying the same client even after
     * an EBADF. Control flow is easier this way than trying to manage an
     * immutable env in the face of exceptions. *)
    let clients = Queue.create () in
    Queue.blit_transfer ~src:env.purgatory_clients ~dst:clients ();
    let env =
      Queue.fold
        ~f:
          begin
            fun env (tracker, handoff_options, client_fd) ->
            try
              client_prehandoff
                ~tracker
                ~is_purgatory_client:true
                env
                handoff_options
                client_fd
            with
            | Unix.Unix_error (Unix.EPIPE, _, _)
            | Unix.Unix_error (Unix.EBADF, _, _) ->
              log "Purgatory client disconnected. Dropping." ~tracker;
              env
          end
        ~init:env
        clients
    in
    env

  let maybe_push_purgatory_clients env =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    match (env.server, Queue.length env.purgatory_clients) with
    | (Alive _, 0) -> env
    | (Died_config_changed, _) ->
      (* These clients are waiting for a server to be started. But this Monitor
       * is waiting for a new client to connect (which confirms to us that we
       * are running the correct version of the Monitor). So let them know
       * that they might want to do something. *)
      push_purgatory_clients env
    | (Alive _, _) -> push_purgatory_clients env
    | (Not_yet_started, _)
    | (Died_unexpectedly _, _) ->
      env

  (* Kill command from client is handled by server server, so the monitor
   * needs to check liveness of the server process to know whether
   * to stop itself. *)
  let update_status_ (env : env) monitor_config =
    let env =
      match env.server with
      | Alive process ->
        let (pid, proc_stat) = SC.wait_pid process in
        (match (pid, proc_stat) with
        | (0, _) ->
          (* "pid=0" means the pid we waited for (i.e. process) hasn't yet died/stopped *)
          env
        | (_, _) ->
          (* "pid<>0" means the pid has died or received a stop signal *)
          let oom_code = Exit_status.(exit_code Out_of_shared_memory) in
          let was_oom =
            match proc_stat with
            | Unix.WEXITED code when code = oom_code -> true
            | _ -> Sys_utils.check_dmesg_for_oom process.pid "hh_server"
          in
          (* Now we run some cleanup if the server died. First off, any FD we're waiting for
          a read-receipt from the server will never be fulfilled, so let's close them.
          The client will get an EOF and think (rightly) that the server hung up. *)
          Sent_fds_collector.collect_garbage
            ~sequence_receipt_high_water_mark:Int.max_value;
          (* Plus any additional cleanup. *)
          SC.on_server_exit monitor_config;
          ServerProcessTools.check_exit_status proc_stat process monitor_config;
          { env with server = Died_unexpectedly (proc_stat, was_oom) })
      | Not_yet_started
      | Died_config_changed
      | Died_unexpectedly _ ->
        env
    in

    let (exit_status, server_state) =
      match env.server with
      | Alive _ -> (None, Informant_sig.Server_alive)
      | Died_unexpectedly (Unix.WEXITED c, _) ->
        (Some c, Informant_sig.Server_dead)
      | Not_yet_started -> (None, Informant_sig.Server_not_yet_started)
      | Died_unexpectedly ((Unix.WSIGNALED _ | Unix.WSTOPPED _), _)
      | Died_config_changed ->
        (None, Informant_sig.Server_dead)
    in
    (env, exit_status, server_state)

  let server_not_started env = { env with server = Not_yet_started }

  let update_status env monitor_config =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    let (env, exit_status, server_state) = update_status_ env monitor_config in
    let informant_report = Informant.report env.informant server_state in
    let is_watchman_fresh_instance =
      match exit_status with
      | Some c when c = Exit_status.(exit_code Watchman_fresh_instance) -> true
      | _ -> false
    in
    let is_watchman_failed =
      match exit_status with
      | Some c when c = Exit_status.(exit_code Watchman_failed) -> true
      | _ -> false
    in
    let is_config_changed =
      match exit_status with
      | Some c when c = Exit_status.(exit_code Hhconfig_changed) -> true
      | _ -> false
    in
    let is_heap_stale =
      match exit_status with
      | Some c
        when (c = Exit_status.(exit_code File_provider_stale))
             || c = Exit_status.(exit_code Decl_not_found) ->
        true
      | _ -> false
    in
    let is_sql_assertion_failure =
      match exit_status with
      | Some c
        when (c = Exit_status.(exit_code Sql_assertion_failure))
             || (c = Exit_status.(exit_code Sql_cantopen))
             || (c = Exit_status.(exit_code Sql_corrupt))
             || c = Exit_status.(exit_code Sql_misuse) ->
        true
      | _ -> false
    in
    let is_worker_error =
      match exit_status with
      | Some c
        when (c = Exit_status.(exit_code Worker_not_found_exception))
             || (c = Exit_status.(exit_code Worker_busy))
             || c = Exit_status.(exit_code Worker_failed_to_send_job) ->
        true
      | _ -> false
    in
    let is_decl_heap_elems_bug =
      match exit_status with
      | Some c when c = Exit_status.(exit_code Decl_heap_elems_bug) -> true
      | _ -> false
    in
    let is_big_rebase =
      match exit_status with
      | Some c when c = Exit_status.(exit_code Big_rebase_detected) -> true
      | _ -> false
    in
    let max_watchman_retries = 3 in
    let max_sql_retries = 3 in
    match (informant_report, env.server) with
    | (Informant_sig.Move_along, Died_config_changed) -> env
    | (Informant_sig.Restart_server _, Died_config_changed) ->
      Hh_logger.log "%s"
      @@ "Ignoring Informant directed restart - waiting for next client "
      ^ "connection to verify server version first";
      env
    | (Informant_sig.Restart_server target_saved_state, _) ->
      Hh_logger.log "Informant directed server restart. Restarting server.";
      HackEventLogger.informant_induced_restart ();
      kill_and_maybe_restart_server ?target_saved_state env exit_status
    | (Informant_sig.Move_along, _) ->
      if
        (is_watchman_failed || is_watchman_fresh_instance)
        && env.watchman_retries < max_watchman_retries
      then (
        Hh_logger.log
          "Watchman died. Restarting hh_server (attempt: %d)"
          (env.watchman_retries + 1);
        let env = { env with watchman_retries = env.watchman_retries + 1 } in
        server_not_started env
      ) else if is_decl_heap_elems_bug then (
        Hh_logger.log "hh_server died due to Decl_heap_elems_bug. Restarting";
        server_not_started env
      ) else if is_worker_error then (
        Hh_logger.log "hh_server died due to worker error. Restarting";
        server_not_started env
      ) else if is_config_changed then (
        Hh_logger.log "hh_server died from hh config change. Restarting";
        server_not_started env
      ) else if is_heap_stale then (
        Hh_logger.log
          "Several large rebases caused shared heap to be stale. Restarting";
        server_not_started env
      ) else if is_big_rebase then (
        Hh_logger.log "Server exited because of big rebase. Restarting";
        server_not_started env
      ) else if is_sql_assertion_failure && env.sql_retries < max_sql_retries
        then (
        Hh_logger.log
          "Sql failed. Restarting hh_server in fresh mode (attempt: %d)"
          (env.sql_retries + 1);
        let env = { env with sql_retries = env.sql_retries + 1 } in
        server_not_started env
      ) else
        env

  let rec check_and_run_loop
      ?(consecutive_throws = 0) env monitor_config (socket : Unix.file_descr) =
    let (env, consecutive_throws) =
      try (check_and_run_loop_ env monitor_config socket, 0) with
      | Unix.Unix_error (Unix.ECHILD, _, _) ->
        let stack = Printexc.get_backtrace () in
        ignore
          (Hh_logger.log
             "check_and_run_loop_ threw with Unix.ECHILD. Exiting. - %s"
             stack);
        Exit.exit Exit_status.No_server_running_should_retry
      | Watchman.Watchman_restarted ->
        Exit.exit Exit_status.Watchman_fresh_instance
      | Exit_status.Exit_with _ as e -> raise e
      | e ->
        let stack = Printexc.get_backtrace () in
        if consecutive_throws > 500 then (
          Hh_logger.log "Too many consecutive exceptions.";
          Hh_logger.log
            "Probably an uncaught exception rethrown each retry. Exiting. %s"
            stack;
          HackEventLogger.uncaught_exception e;
          Exit.exit Exit_status.Uncaught_exception
        );
        Hh_logger.log
          "check_and_run_loop_ threw with exception: %s - %s"
          (Exn.to_string e)
          stack;
        (env, consecutive_throws + 1)
    in
    check_and_run_loop ~consecutive_throws env monitor_config socket

  and check_and_run_loop_ env monitor_config (socket : Unix.file_descr) =
    (* WARNING! Don't use the (slow) HackEventLogger here, in the inner loop non-failure path. *)
    (* That's because HackEventLogger for the monitor is synchronous and takes 50ms/call. *)
    (* But the monitor's non-failure inner loop must handle hundres of clients per second *)
    let lock_file = monitor_config.lock_file in
    if not (Lock.grab lock_file) then (
      Hh_logger.log "Lost lock; terminating.\n%!";
      HackEventLogger.lock_stolen lock_file;
      Exit.exit Exit_status.Lock_stolen
    );
    let sequence_receipt_high_water_mark =
      match env.server with
      | ServerProcess.Alive process_data ->
        let pid = process_data.ServerProcess.pid in
        MonitorRpc.read_server_receipt_to_monitor_file
          ~server_receipt_to_monitor_file:
            (ServerFiles.server_receipt_to_monitor_file pid)
        |> Option.value ~default:0
      | _ -> 0
    in
    let env = maybe_push_purgatory_clients env in
    (* The first sequence number we send is 1; hence, the default "0" will be a no-op *)
    let () =
      Sent_fds_collector.collect_garbage ~sequence_receipt_high_water_mark
    in
    let has_client = sleep_and_check socket in
    let env = update_status env monitor_config in
    if not has_client then
      (* Note: this call merely reads from disk; it doesn't go via the slow HackEventLogger. *)
      let () = EventLogger.recheck_disk_files () in
      env
    else
      try
        let (fd, _) = Unix.accept socket in
        try ack_and_handoff_client env fd with
        | Exit_status.Exit_with _ as e -> raise e
        | e ->
          let e = Exception.wrap e in
          Hh_logger.log
            "Ack_and_handoff failure; closing client FD: %s"
            (Exception.get_ctor_string e);
          Unix.close fd;
          env
      with
      | Exit_status.Exit_with _ as e -> raise e
      | e ->
        HackEventLogger.accepting_on_socket_exception e;
        Hh_logger.log
          "Accepting on socket failed. Ignoring client connection attempt.";
        env

  let check_and_run_loop_once (env, monitor_config, socket) =
    let env = check_and_run_loop_ env monitor_config socket in
    (env, monitor_config, socket)

  let start_monitor
      ~current_version
      ~waiting_client
      ~max_purgatory_clients
      ~monitor_fd_close_delay
      ~monitor_backpressure
      server_start_options
      informant_init_env
      monitor_config =
    let socket = Socket.init_unix_socket monitor_config.socket_file in
    (* If the client started the server, it opened an FD before forking, so it
     * can be notified when the monitor socket is ready. The FD number was
     * passed in program args. *)
    Option.iter waiting_client (fun fd ->
        let oc = Unix.out_channel_of_descr fd in
        try
          Out_channel.output_string oc (ServerMonitorUtils.ready ^ "\n");
          Out_channel.close oc
        with
        | (Sys_error _ | Unix.Unix_error _) as e ->
          Printf.eprintf
            "Caught exception while waking client: %s\n%!"
            (Exn.to_string e));

    (* It is essential that we initiate the Informant before the server if we
     * want to give the opportunity for the Informant to truly take
     * ownership over the lifetime of the server.
     *
     * This is because start_server won't actually start a server if it sees
     * a hg update sentinel file indicating an hg update is in-progress.
     * Starting the informant first ensures that its Watchman watch is started
     * before we check for the hgupdate sentinel file - this is required
     * for the informant to properly observe an update is complete without
     * hitting race conditions. *)
    let informant = Informant.init informant_init_env in
    let server_process =
      maybe_start_first_server server_start_options informant
    in
    let env =
      {
        informant;
        max_purgatory_clients;
        current_version;
        purgatory_clients = Queue.create ();
        server = server_process;
        server_start_options;
        retries = 0;
        sql_retries = 0;
        watchman_retries = 0;
        ignore_hh_version =
          Informant.should_ignore_hh_version informant_init_env;
        monitor_fd_close_delay;
        monitor_backpressure;
      }
    in
    (env, monitor_config, socket)

  let start_monitoring
      ~current_version
      ~waiting_client
      ~max_purgatory_clients
      ~monitor_fd_close_delay
      ~monitor_backpressure
      server_start_options
      informant_init_env
      monitor_config =
    let (env, monitor_config, socket) =
      start_monitor
        ~current_version
        ~waiting_client
        ~max_purgatory_clients
        ~monitor_fd_close_delay
        ~monitor_backpressure
        server_start_options
        informant_init_env
        monitor_config
    in
    check_and_run_loop env monitor_config socket
end
