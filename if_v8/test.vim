so <sfile>:p:h/init.vim

let s:test = {}

" test1: hello world
function s:test.test1()
  V8 print("hello, world")
endfunction

" test2: exception: v8 -> vim
function s:test.test2()
  try
    V8 throw "error from v8"
  catch
    echo printf('caught in vim "%s"', v:exception)
  endtry
endfunction

" test3: exception: vim -> v8
function s:test.test3()
  V8 try { vim.execute('throw "error from vim"') } catch (e) { print('caught in v8 "' + e + '"'); }
endfunction

" test4: exception: vim -> v8 -> vim
function s:test.test4()
  try
    V8 vim.execute('throw "error from vim"')
  catch
    echo printf('caught in vim "%s"', v:exception)
  endtry
endfunction

" test5: accessing local variable
function s:test.test5()
  let x = 1
  " We have to use eval() trick to execute v8 script in the caller context.
  " Otherwise we cannot access function local variable.
  V8 print(vim.eval("x"))
  V8 vim.let("x", 2)
  echo x
  " Of course, V8Eval can be used.
  let x = V8Eval('1 + 2')
  echo x
endfunction

" test6: invoking vim's function
function s:test.test6()
  new
  V8 vim.append("$", "line1")
  redraw! | sleep 200m
  V8 vim.append("$", "line1")
  redraw! | sleep 200m
  V8 vim.append("$", "line1")
  redraw! | sleep 200m
  quit!
endfunction

" test7: recursive object: vim -> v8
function s:test.test7()
  let x = {}
  let x.x = x
  let y = []
  let y += [y]
  V8 var x = vim.eval("x")
  V8 var y = vim.eval("y")
  V8 if (x === x.x) { print("x === x.x"); } else { throw "x !== x.x"; }
  V8 if (y === y[0]) { print("y === y[0]"); } else { throw "y !== y[0]"; }
endfunction

" test8: recursive object: v8 -> vim
function s:test.test8()
  V8 var x = {}
  V8 x.x = x
  V8 var y = []
  V8 y[0] = y
  let x = V8Eval('x')
  let y = V8Eval('y')
  if x is x.x
    echo "x is x.x"
  else
    throw "x isnot x.x"
  endif
  if y is y[0]
    echo "y is y[0]"
  else
    throw "y isnot y[0]"
  endif
endfunction

" test9: VimList 1
function s:test.test9()
  let x = [1, 2, 3]
  echo x
  V8 var x = vim.eval('x')
  V8 x[0] += 100; x[1] += 100; x[2] += 100;
  echo x
  if x[0] != 101 || x[1] != 102 || x[2] != 103
    throw "test9 faield"
  endif
endfunction

" test10: VimList 2
function s:test.test10()
  V8 var x = new vim.List()
  V8 vim.extend(x, [1, 2, 3])
  let x = V8Eval('x')
  echo x
  let x[0] += 100
  let x[1] += 100
  let x[2] += 100
  V8 print(x[0] + " " + x[1] + " " + x[2])
  V8 if (x[0] != 101 || x[1] != 102 || x[2] != 103) { throw "test10 failed"; }
endfunction

" test11: VimDict 1
function s:test.test11()
  let x = {}
  V8 var x = vim.eval("x")
  V8 x["apple"] = "orange"
  V8 x[9] = "nine"
  echo x
  if x["apple"] != "orange" || x[9] != "nine"
    throw "test11 failed"
  endif
endfunction

" test12: VimDict 2
function s:test.test12()
  V8 var x = new vim.Dict()
  let x = V8Eval('x')
  let x["apple"] = "orange"
  let x[9] = "nine"
  V8 print('x["apple"] = ' + x["apple"])
  V8 print('x[9] = ' + x[9])
  V8 if (x["apple"] != "orange" || x[9] != "nine") { throw "test12 failed"; }
endfunction

let s:d = {}
let s:d.name = 'd'
function s:d.func()
  echo "my name is " . self.name
  return self
endfunction
function s:d.raise(msg)
  throw a:msg
endfunction
let s:d.printf = function("printf")

let s:e = {}
let s:e.name = 'e'

" test13: VimFunc
function s:test.test13()
  call eval(V8ExecuteX('var d = vim.eval("s:d")'))
  call eval(V8ExecuteX('var e = vim.eval("s:e")'))
  V8 if (d.func() !== d) { throw "test13 failed"; }
  V8 e.func = d.func
  V8 if (e.func() !== e) { throw "test13 failed"; }
  V8 print(d.printf("%s", "This is printf"))
endfunction

" test15: VimFunc Exception
function s:test.test15()
  call eval(V8ExecuteX('var d = vim.eval("s:d")'))
  try
    V8 d.raise("error from vimfunc")
    let x = 1
  catch
    echo printf('caught in vim "%s"', v:exception)
  endtry
  if exists('x')
    throw "test15 failed"
  endif
endfunction

function! s:mysort(a, b)
  let a = matchstr(a:a, '\d\+')
  let b = matchstr(a:b, '\d\+')
  return a - b
endfunction

try
  for s:name in sort(keys(s:test), 's:mysort')
    echo "\n" . s:name . "\n"
    call s:test[s:name]()
    " XXX: message is not shown when more prompt is not fired.
    sleep 100m
  endfor
endtry
