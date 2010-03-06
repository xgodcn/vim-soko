
if exists("current_compiler")
  finish
endif
let current_compiler = "pyflakes"

if exists(":CompilerSet") != 2
  command -nargs=* CompilerSet setlocal <args>
endif

CompilerSet makeprg=pyflakes\ %

" import a
" import a.b <- ignore message for this
CompilerSet errorformat=%-G%f:%l:\ redefinition\ of\ unused\ %.%#
"
CompilerSet errorformat+=%f:%l:\ %m
