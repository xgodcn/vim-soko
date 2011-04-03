
if exists("current_compiler")
  finish
endif
let current_compiler = "jslint"

CompilerSet makeprg=jslint
      \\ $*
      \\ %

CompilerSet errorformat=
      \%E%f:%l:%c:error:%m,
      \%W%f:%l:%c:warning:%m

