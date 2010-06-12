
if exists("current_compiler")
  finish
endif
let current_compiler = "phpmd"

CompilerSet makeprg=phpmd
      \\ %
      \\ text
      \\ codesize,naming,unusedcode
      \\ $*

CompilerSet errorformat=
      \%E%f:%l%m,
      \%-G\\s%#

