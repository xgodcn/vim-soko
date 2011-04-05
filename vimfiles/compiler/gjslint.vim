" [Closure Linter]
" http://code.google.com/closure/utilities/

if exists("current_compiler")
  finish
endif
let current_compiler = "gjslint"

CompilerSet makeprg=gjslint
      \\ --unix_mode
      \\ $*
      \\ %

CompilerSet errorformat=
      \%f:%l:%m,
      \%+ATraceback%.%#,
      \%+C\ %.%#,
      \%+Z%\\S%.%#,
      \%-G%.%#

