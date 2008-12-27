
let s:dir = expand('<sfile>:p:h')
let s:dll = s:dir . '/if_v8' . (has('win32') ? '.dll' : '.so')
let s:runtime = [
      \ s:dir . '/runtime.js',
      \ s:dir . '/vson.js',
      \ ]

function! V8Init()
  if exists('s:init')
    return
  endif
  let s:init = 1
  echo libcall(s:dll, 'init', s:dll)
  for file in s:runtime
    call V8Load(file)
  endfor
endfunction

function! V8ExecuteX(expr)
  return printf("libcall(\"%s\", 'execute', \"%s\")", escape(s:dll, '\"'), escape(a:expr, '\"'))
endfunction

function! V8LoadX(file)
  return V8ExecuteX(printf('load("%s")', escape(a:file, '\"')))
endfunction

function! V8EvalX(expr)
  let x = V8ExecuteX(printf("vim.let('g:._____v8_res', eval(\"%s\"))", '(' . escape(a:expr, '\"') . ')'))
  return printf("eval(get({}, %s, 'g:._____v8_res'))", x)
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

function! VsonEncode(v, ...) abort
  let level = get(a:000, 0, 1)

  if level == 1
    " check cyclic reference
    " E698: variable nested too deep for making a copy
    call deepcopy(a:v, 1)
  endif

  let str_escape = {
        \ '"' : '\"',
        \ '\' : '\\',
        \ '/' : '\/',
        \ "\b" : '\b',
        \ "\f" : '\f',
        \ "\n" : '\n',
        \ "\r" : '\r',
        \ "\t" : '\t',
        \ }

  let v = a:v
  if type(v) == type(0)
    return string(v)
  elseif type(v) == type(0.0)
    return string(v)
  elseif type(v) == type("")
    return '"' . substitute(v, '["\\/\b\f\n\r\t]', '\=str_escape[submatch(0)]', 'g') . '"'
  elseif type(v) == type([])
    return '[' . join(map(copy(v), 'VsonEncode(v:val, level + 1)'), ',') . ']'
  elseif type(v) == type({})
    return '{' . join(map(keys(v), 'VsonEncode(v:val, level + 1) . ":" . VsonEncode(v[v:val], level + 1)'), ',') . '}'
  elseif type(v) == type(function('tr'))
    return VsonEncode(string(v), level + 1)
  endif
endfunction

function! VsonDecode(json)
  let [null, false, true] = [0, 0, 1]
  " Since vim doesn't support empty key, replace it.
  let json = substitute(a:json, '""\_s*:', '"[EMPTY]":', 'g')
  return eval(json)
endfunction

call V8Init()
