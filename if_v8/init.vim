
command! V8Start let s:script = []
command! V8End execute s:V8CommandX(join(s:script, "\n") . "\n", !exists('l:'), 1)
command! -nargs=+ V8 execute s:V8CommandX(<q-args>, !exists('l:'), 0)

" This is a trick to access variable in the caller context (g:, l:)
" We cannot access s: variable with this trick because user defined
" command is executed in a script context where it defined.
function! s:V8CommandX(cmd, interactive, end)
  if a:end
    unlet s:script
  endif
  if exists('s:script')
    call add(s:script, a:cmd)
    return ''
  endif
  if a:interactive
    " interactive mode
    return ""
        \ . "try\n"
        \ . "  let v:['%v8_print%'] = ''\n"
        \ . "  echo expand('<args>')\n"
        \ . "  call eval(V8ExecuteX(\"" . escape(a:cmd, '\"') . "\"))\n"
        \ . "  echo v:['%v8_print%']\n"
        \ . "catch\n"
        \ . "  echohl Error\n"
        \ . "  for line in split(v:['%v8_errmsg%'], '\\n')\n"
        \ . "    echomsg line\n"
        \ . "  endfor\n"
        \ . "  echohl None\n"
        \ . "endtry\n"
  else
    return "call eval(V8ExecuteX(\"" . escape(a:cmd, '\"') . "\"))\n"
  endif
endfunction

let s:dir = expand('<sfile>:p:h')
let s:dll = s:dir . '/if_v8' . (has('win32') ? '.dll' : '.so')
let s:runtime = [
      \ s:dir . '/runtime.js',
      \ ]

function! s:V8Init() abort
  if exists('s:init')
    return
  endif
  let s:init = 1
  let err = libcall(s:dll, 'init', s:dll)
  if err != ''
    echoerr err
  endif
  for file in s:runtime
    call libcall(s:dll, 'execute', printf("load(\"%s\")", escape(file, '\"')))
  endfor
endfunction

function! V8ExecuteX(expr)
  return printf("libcall(\"%s\", 'execute', \"%s\")", escape(s:dll, '\"'), escape(a:expr, '\"'))
endfunction

function! V8LoadX(file)
  return V8ExecuteX(printf('load("%s")', escape(a:file, '\"')))
endfunction

function! V8EvalX(expr)
  let x = V8ExecuteX(printf("vim.let('v:[\"%%v8_result%%\"]', eval(\"%s\"))", '(' . escape(a:expr, '\"') . ')'))
  return printf("eval(get({}, %s, 'v:[\"%%v8_result%%\"]'))", x)
endfunction

function! V8Load(file)
  return eval(V8LoadX(a:file))
endfunction

function! V8Execute(expr)
  return eval(V8ExecuteX(a:expr))
endfunction

function! V8Eval(expr)
  return eval(V8EvalX(a:expr))
endfunction

call s:V8Init()
