" PHP_CodeSniffer
" http://pear.php.net/package/PHP_CodeSniffer

if exists("current_compiler")
  finish
endif
let current_compiler = "phpcs"

CompilerSet makeprg=phpcs
      \\ --report=csv
      \\ $*
      \\ %

CompilerSet errorformat=
      \%E\"%f\"\\,%l\\,%c\\,error\\,\"%m\",
      \%W\"%f\"\\,%l\\,%c\\,warning\\,\"%m\",
      \%-GFile\\,Line\\,Column\\,Severity\\,Message

