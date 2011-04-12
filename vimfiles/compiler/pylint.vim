" pylint: python code static checker
" http://pypi.python.org/pypi/pylint

if exists("current_compiler")
  finish
endif
let current_compiler = "pylint"

CompilerSet makeprg=pylint
      \\ --reports=n
      \\ --include-ids=y
      \\ --output-format=parseable
      \\ $*
      \\ %

CompilerSet errorformat=
      \%f:%l:\ %m,
      \%-GNo\ config\ file\ found\\,\ using\ default\ configuration

