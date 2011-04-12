" php --syntax-check

if exists("current_compiler")
  finish
endif
let current_compiler = "php"

CompilerSet makeprg=php
      \\ --syntax-check
      \\ $*
      \\ %

CompilerSet errorformat=
      \%EPHP\ Parse\ error:\ %m\ in\ %f\ on\ line\ %l,
      \%-GErrors\ parsing\ %f,
      \%-GNo\ Syntax\ errors\ detected\ in\ %f

