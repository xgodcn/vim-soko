
if exists("current_compiler")
  finish
endif
let current_compiler = "pep8"

CompilerSet makeprg=pep8
      \\ $*
      \\ %

CompilerSet errorformat=
      \%f:%l:%c:\ %m

