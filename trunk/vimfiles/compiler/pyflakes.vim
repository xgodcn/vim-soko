" pyflakes: passive checker of Python programs
" http://pypi.python.org/pypi/pyflakes

if exists("current_compiler")
  finish
endif
let current_compiler = "pyflakes"

CompilerSet makeprg=pyflakes
      \\ $*
      \\ %

CompilerSet errorformat=
      \%f:%l:\ %m

