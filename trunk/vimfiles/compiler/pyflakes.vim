
if exists("current_compiler")
  finish
endif
let current_compiler = "pyflakes"

if exists(":CompilerSet") != 2
  command -nargs=* CompilerSet setlocal <args>
endif

CompilerSet makeprg=pyflakes\ %

CompilerSet errorformat=%f:%l:\ %m

