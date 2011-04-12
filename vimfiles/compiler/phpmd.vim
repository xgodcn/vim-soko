" PHPMD - PHP Mess Detector
" http://phpmd.org/

if exists("current_compiler")
  finish
endif
let current_compiler = "phpmd"

CompilerSet makeprg=phpmd
      \\ %
      \\ text
      \\ codesize,naming,unusedcode,design
      \\ $*

CompilerSet errorformat=
      \%E%f:%l%m,
      \%-G\\s%#

