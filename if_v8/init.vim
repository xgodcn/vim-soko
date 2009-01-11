
command! V8Start call s:lib.v8start()
command! V8End execute V8End()
command! -nargs=+ V8 execute V8(<q-args>, !exists('l:'), 0)

function! V8End()
  return s:lib.v8end()
endfunction

function! V8(...)
  return call(s:lib.v8execute, a:000, s:lib)
endfunction

" usage:
"   :let res = eval(V8Eval('3 + 4'))
function! V8Eval(expr)
  let expr = s:lib.v8expr(printf("vim.let('v:[\"%%v8_result%%\"]', eval(\"%s\"))", '(' . escape(a:expr, '\"') . ')'))
  return printf("eval(get({}, %s, 'v:[\"%%v8_result%%\"]'))", expr)
endfunction



let s:lib = {}

let s:lib.dir = expand('<sfile>:p:h')
let s:lib.dll = s:lib.dir . '/if_v8' . (has('win32') ? '.dll' : '.so')
let s:lib.runtime = [
      \ s:lib.dir . '/runtime.js',
      \ ]

function s:lib.init() abort
  if exists('s:init')
    return
  endif
  let s:init = 1
  let err = libcall(self.dll, 'init', self.dll)
  if err != ''
    echoerr err
  endif
  for file in self.runtime
    call libcall(self.dll, 'execute', printf("load(\"%s\")", escape(file, '\"')))
  endfor
endfunction

function s:lib.v8start()
  let self.script = []
endfunction

function s:lib.v8end()
  return self.v8execute(join(self.script, "\n") . "\n", 0, 1)
endfunction

function s:lib.v8execute(cmd, ...)
  let interactive = get(a:000, 0, 0)
  let end = get(a:000, 1, 1)
  if end
    unlet self.script
  endif
  if exists('self.script')
    call add(self.script, a:cmd)
    return ''
  endif
  let cmd = self.v8expr(a:cmd)
  if interactive
    " interactive mode
    return ""
        \ . "try\n"
        \ . "  let v:['%v8_print%'] = ''\n"
        \ . "  echo expand('<args>')\n"
        \ . "  call eval(\"" . escape(cmd, '\"') . "\")\n"
        \ . "  echo v:['%v8_print%']\n"
        \ . "catch\n"
        \ . "  echohl Error\n"
        \ . "  for line in split(v:['%v8_errmsg%'], '\\n')\n"
        \ . "    echomsg line\n"
        \ . "  endfor\n"
        \ . "  echohl None\n"
        \ . "endtry\n"
  else
    return "call eval(\"" . escape(cmd, '\"') . "\")"
  endif
endfunction

function s:lib.v8expr(expr)
  return printf("libcall(\"%s\", 'execute', \"%s\")", escape(self.dll, '\"'), escape(a:expr, '\"'))
endfunction

call s:lib.init()
