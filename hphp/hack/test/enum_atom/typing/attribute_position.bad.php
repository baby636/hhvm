<?hh
<<file:__EnableUnstableFeatures('enum_atom')>>

enum class E : mixed {
  int Age = 42;
  string Name = "zuck";
}

function ok_arg0<T>(<<__Atom>>HH\MemberOf<E, T> $e, int $_, string $_) : T {
  return $e;
}

function ko_arg1<T>(int $_, <<__Atom>>HH\MemberOf<E, T> $e, string $_) : T {
  return $e;
}

function ko_arg2<T>(int $_, string $_, <<__Atom>>HH\MemberOf<E, T> $e) : T {
  return $e;
}

function ko_multiple0<T>(
  <<__Atom>>HH\MemberOf<E, T> $e,
  int $_,
  <<__Atom>>HH\MemberOf<E, T> $_,
  int $_,
  HH\MemberOf<E, T> $_,
  int $_,
  <<__Atom>>HH\MemberOf<E, T> $_,
  int $_
  ) : T {
  return $e;
}

function ko_multiple1<T>(
  HH\MemberOf<E, T> $e,
  int $_,
  <<__Atom>>HH\MemberOf<E, T> $_,
  int $_,
  <<__Atom>>HH\MemberOf<E, T> $_,
  int $_,
  <<__Atom>>HH\MemberOf<E, T> $_,
  int $_
  ) : T {
  return $e;
}
