if exists("current_compiler")
  finish
endif
let current_compiler = "pylint"

CompilerSet makeprg=pylint
      \\ --reports=n
      \\ --include-ids=y
      \\ --output-format=parseable
      \\ %

CompilerSet errorformat& errorformat+=
      \%-GNo\ config\ file\ found\\,\ using\ default\ configuration

