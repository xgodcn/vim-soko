
if exists("current_compiler")
  finish
endif
let current_compiler = "php"

CompilerSet makeprg=php
      \\ -d\ short_open_tag=0
      \\ --syntax-check
      \\ $*
      \\ %

CompilerSet errorformat=
      \%EPHP\ Parse\ error:\ %m\ in\ %f\ on\ line\ %l,
      \%-GErrors\ parsing\ %f,
      \%-GNo\ Syntax\ errors\ detected\ in\ %f

