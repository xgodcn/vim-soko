
if exists("current_compiler")
  finish
endif
let current_compiler = "pyflakes"

CompilerSet makeprg=pyflakes
      \\ $*
      \\ %

CompilerSet errorformat=
      \%f:%l:\ %m

" import a
" import a.b <- ignore message for this
CompilerSet errorformat+=%-G%f:%l:\ redefinition\ of\ unused\ %.%#

