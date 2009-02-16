augroup QuickCheck
  au!
  autocmd InsertLeave * if &ft == 'php' | call s:FindUnusedVar() | endif
  autocmd BufWritePost * if &ft == 'php' | call s:PhpLint() | endif
augroup END

hi default link MarkerError Error

function! s:PhpLint()
  if !executable('php')
    return
  endif
  let cmd = 'php -l ' . shellescape(expand('%'))
  let msg = system(cmd)
  if v:shell_error
    echoerr cmd
    echohl Error
    for line in split(msg, '\n')
      echomsg line
    endfor
    echohl None
  endif
endfunction

function! s:FindUnusedVar()
  let view = winsaveview()
  let funcstart = search('\<function\>', 'bW')
  let start = search('{', 'W')
  let end = searchpair('{', '', '}')
  call winrestview(view)
  if funcstart == 0 || start == 0 || end == 0
    return
  endif
  if funcstart == start
    let start += 1
  endif
  call s:MatchDeleteGroup('MarkerError')
  let head = join(getline(funcstart, start - 1), "\n")
  let body = join(getline(start, end), "\n")
  let args = s:MatchListAll(head, '\v\$(\w+)')
  let vars = s:MatchListAll(body, '\v%((as\s+|\=\>\s*)@<=)?\$(\w+)(\s*\=)?')
  let keys = s:MatchListAll(body, '\v[''"](\w+)[''"]')
  let special = ['$this', '$_GET', '$_POST', '$_REQUEST']
  let assigned = map(copy(args), 'v:val[0]')
  let words = map(args + keys, 'v:val[0]')
  let words += map(copy(vars), '"$".v:val[2]')
  for m in vars
    let word = '$' . m[2]
    if index(special, word) != -1
      continue
    endif
    if m[1] != '' || m[3] != ''
      call add(assigned, word)
    endif
    if index(assigned, word) == -1 || count(words, word) == 1
      call matchadd('MarkerError', '\V' . escape(word, '\'))
    endif
  endfor
  for m in keys
    let word = '$' . m[2]
    if count(words, word) == 1
      call matchadd('MarkerError', '\V' . escape(word, '\'))
    endif
  endfor
endfunction

function! s:CountWord(words)
  let wordcounts = {}
  for word in a:words
    let wordcounts[word] = get(wordcounts, word, 0) + 1
  endfor
  return wordcounts
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

function! s:MatchExists(group)
  for m in getmatches()
    if m.group ==# a:group
      return 1
    endif
  endfor
  return 0
endfunction

