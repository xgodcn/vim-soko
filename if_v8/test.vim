so <sfile>:p:h/init.vim

let s:test = {}

" test1: hello world
function s:test.test1()
  call V8Execute('print("hello, world")')
endfunction

" test2: exception: v8 -> vim
function s:test.test2()
  try
    call V8Execute('throw "error from v8"')
  catch
    echo printf('caught in vim "%s"', v:exception)
  endtry
endfunction

" test3: exception: vim -> v8
function s:test.test3()
  call V8Execute("try { vim.execute('throw \"error from vim\"'); } catch (e) { print('caught in v8 \"' + e + '\"'); }")
endfunction

" test4: exception: vim -> v8 -> vim
function s:test.test4()
  try
    call V8Execute("vim.execute('throw \"error from vim\"')")
  catch
    echo printf('caught in vim "%s"', v:exception)
  endtry
endfunction

" test5: accessing local variable
function s:test.test5()
  let x = 1
  " We have to use eval() trick to execute v8 script in the caller context.
  " Otherwise we cannot access function local variable.
  call eval(V8ExecuteX('print(vim.eval("x")); vim.let("x", 2);'))
  echo x
  " Of course, V8Eval can be used.
  let x = V8Eval('1 + 2')
  echo x
endfunction

" test6: passing value using vson
function s:test.test6()
  let x = 1
  call V8Execute(printf('print(%s)', VsonEncode(x)))
  let json = V8Eval('vim.VSON.stringify([1, 2, 3])')
  echo VsonDecode(json)
endfunction

" test7: invoking vim's function
function s:test.test7()
  new
  call V8Execute('vim.append("$", "line1")')
  redraw! | sleep 500m
  call V8Execute('vim.append("$", "line2")')
  redraw! | sleep 500m
  call V8Execute('vim.append("$", "line3")')
  redraw! | sleep 500m
  quit!
endfunction

for s:name in sort(keys(s:test))
  echo "\n" . s:name . "\n"
  call s:test[s:name]()
endfor
