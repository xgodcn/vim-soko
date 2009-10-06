" highlight unused/unassigned local variable.
" Last Change: 2009-10-07

if exists("b:did_ftplugin")
  finish
endif

let s:save_cpo = &cpo
set cpo&vim

hi default link PhpLocalVarCheckError Error

augroup PhpLocalVarCheck
  au! * <buffer>
  autocmd FileType <buffer> if &ft != 'php' | call s:Uninstall() | endif
  autocmd CursorMoved <buffer> call s:LocalVarCheck()
augroup END

function! s:Uninstall()
  au! PhpLocalVarCheck * <buffer>
  " TODO: How to remove from other window?
  call s:MatchDeleteGroup('PhpLocalVarCheckError')
  unlet! w:php_localvarcheck_changedtick
  unlet! w:php_localvarcheck_start
  unlet! w:php_localvarcheck_end
endfunction

function! s:LocalVarCheck()
  if get(w:, 'php_localvarcheck_changedtick', 0) == b:changedtick
        \ && get(w:, 'php_localvarcheck_start', 0) <= line('.')
        \ && get(w:, 'php_localvarcheck_end', 0) >= line('.')
    return
  endif
  let view = winsaveview()
  let [start, startcol] = searchpos('\c\v<function>', 'bWc')
  while start != 0 && synIDattr(synID(line('.'), col('.'), 0), 'name') =~? 'string\|comment'
    let [start, startcol] = searchpos('\c\v<function>', 'bW')
  endwhile
  if start != 0
    let open = search('{', 'W')
    while open != 0 && synIDattr(synID(line('.'), col('.'), 0), 'name') =~? 'string\|comment'
      let open = search('{', 'W')
    endwhile
  endif
  if start != 0 && open != 0
    let [end, endcol] = searchpairpos('{', '', '}', 'W',
          \ 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\\|comment"')
  endif
  call winrestview(view)
  if start == 0 || open == 0 || end == 0 || end < line('.')
    call s:MatchDeleteGroup('PhpLocalVarCheckError')
    let w:php_localvarcheck_changedtick = b:changedtick
    let w:php_localvarcheck_start = 0
    let w:php_localvarcheck_end = 0
  else
    let lines = getline(start, end)
    let lines[-1] = lines[-1][0 : endcol - 1]
    let lines[0] = lines[0][startcol - 1 : ]
    call s:MatchDeleteGroup('PhpLocalVarCheckError')
    for pat in s:FindErrorVariable(join(lines, "\n"))
      call matchadd('PhpLocalVarCheckError', pat)
    endfor
    let w:php_localvarcheck_changedtick = b:changedtick
    let w:php_localvarcheck_start = start
    let w:php_localvarcheck_end = end
  endif
endfunction

function! s:FindErrorVariable(src)
  let special = {'$GLOBALS':1,'$_SERVER':1,'$_GET':1,'$_POST':1,'$_REQUEST':1,'$_FILES':1,'$_COOKIE':1,'$_SESSION':1,'$_ENV':1,'$this':1}
  let global = {}
  let assigned = {}
  let used = {}
  let patterns = {}
  for [var, is_assign, is_global] in s:Parse(a:src)
    if has_key(special, var)
      continue
    endif
    if is_assign
      let assigned[var] = 1
      " global variable may be used in somewhere else.
      if is_global
        let global[var] = 1
      elseif has_key(global, var)
        let used[var] = 1
      endif
    else
      let used[var] = 1
      if !has_key(assigned, var)
        let patterns['\V' . escape(var, '\') . '\>'] = 1
      endif
    endif
  endfor
  for var in keys(assigned)
    if !has_key(used, var)
      let patterns['\V' . escape(var, '\') . '\>'] = 1
    endif
  endfor
  return keys(patterns)
endfunction

" @return [['$varname', is_assign, is_global], ...]
function! s:Parse(src)
  let pat_syntax  = '\c\v('
        \ . '#.{-}\n'
        \ . '|//.{-}\n'
        \ . '|/\*.{-}\*/'
        \ . "|'[^']*'"
        \ . '|"%(\\.|[^"])*"'
        \ . '|\<\<\<\s*''\w+'''
        \ . '|\<\<\<\s*\w+'
        \ . '|\$\w+'
        \ . '|<as>'
        \ . '|<list>'
        \ . '|<static>'
        \ . '|<global>'
        \ . '|[;(){}]'
        \ . ')'
  let head = 1
  let items = []
  " parse args
  let i = match(a:src, pat_syntax)
  while i != -1
    let s = matchstr(a:src, pat_syntax, i)
    if s[0] == ')'
      break
    elseif s[0] == '$'
      call add(items, [s, 1, 0])
      let e = i + len(s)
    else
      let e = i + len(s)
    endif
    let i = match(a:src, pat_syntax, e)
  endwhile
  if i == -1
    " error
    return items
  endif
  " parse body
  while i != -1
    let s = matchstr(a:src, pat_syntax, i)
    if s[0] == '"'
      for var in s:MatchStrAll(s, '\v\\.|\$\w+')
        if var[0] == '$'
          call add(items, [var, 0, 0])
        endif
      endfor
      let e = i + len(s)
    elseif s[0] == '<'
      let mark = matchstr(a:src, '\w\+', i)
      let j = match(a:src, '\n' . mark . ';', i + len(s))
      if j == -1
        " error
        break
      endif
      if s != "'$"
        for var in s:MatchStrAll(a:src[i + len(s) : j], '\v\\.|\$\w+')
          if var[0] == '$'
            call add(items, [var, 0, 0])
          endif
        endfor
      endif
      let e = j + len("\n" . mark . ';')
    elseif s[0] == '$'
      if match(a:src, '^\_s*=[^=>]', i + len(s)) != -1
        call add(items, [s, 1, 0])
      else
        call add(items, [s, 0, 0])
      endif
      let e = i + len(s)
    elseif s ==? 'as'
      let _ = matchlist(a:src, '\c\vas%(\_s|&)*(\$\w+)%(\_s*\=\>%(\_s|&)*(\$\w+))?', i)
      if empty(_)
        " error
        break
      endif
      call add(items, [_[1], 1, 0])
      if _[2] != ''
        call add(items, [_[2], 1, 0])
      endif
      let e = i + len(_[0])
    elseif s ==? 'list'
      let j = match(a:src, pat_syntax, i + len(s))
      while j != -1
        let t = matchstr(a:src, pat_syntax, j)
        if t == ')'
          break
        elseif t[0] == '$'
          call add(items, [t, 1, 0])
        endif
        let j = match(a:src, pat_syntax, j + len(t))
      endwhile
      if j == -1
        " error
        break
      endif
      let e = j
    elseif s ==? 'static'
      let j = match(a:src, pat_syntax, i + len(s))
      while j != -1
        let t = matchstr(a:src, pat_syntax, j)
        if t == ';'
          break
        elseif t[0] == '$'
          call add(items, [t, 1, 0])
        endif
        let j = match(a:src, pat_syntax, j + len(t))
      endwhile
      if j == -1
        " error
        break
      endif
      let e = j
    elseif s ==? 'global'
      let j = match(a:src, pat_syntax, i + len(s))
      while j != -1
        let t = matchstr(a:src, pat_syntax, j)
        if t == ';'
          break
        elseif t[0] == '$'
          call add(items, [t, 1, 1])
        endif
        let j = match(a:src, pat_syntax, j + len(t))
      endwhile
      if j == -1
        " error
        break
      endif
      let e = j
    else
      let e = i + len(s)
    endif
    let i = match(a:src, pat_syntax, e)
  endwhile
  return items
endfunction

function! s:MatchStrAll(text, pat)
  let matches = []
  call substitute(a:text, a:pat, '\=empty(add(matches, submatch(0)))', 'g')
  return matches
endfunction

function! s:MatchListAll(text, pat)
  let matches = []
  call substitute(a:text, a:pat, '\=empty(add(matches, map(range(10), "submatch(v:val)")))', 'g')
  return matches
endfunction

function! s:MatchDeleteGroup(group)
  for m in getmatches()
    if m.group ==# a:group
      call matchdelete(m.id)
    endif
  endfor
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
