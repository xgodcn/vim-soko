" 2007-02-12

scriptencoding utf-8

let s:cpo_save = &cpo
set cpo&vim

let s:name = expand("<sfile>:t:r")
let b:keymap_name = s:name
let s:im = {s:name}#import()

augroup ImPlug
  au! * <buffer>
  autocmd BufEnter <buffer> call s:OnBufEnter()
  autocmd BufLeave <buffer> call s:OnBufLeave()
augroup END

if exists("b:im_context")
  unlet b:im_context
endif

function! s:install_key_mapping()
  for k in filter(values(s:im.kmap), 'v:val.map != ""')
    if !has("gui_running") && k.map =~? '<Esc>\|<C-[>'
      " When using CUI and function key code is started with <Esc>, we
      " cannot map <Esc> only.  For example, in xterm <F9> generates key
      " sequence ["\<Esc>", "[", "2", "0", "~"].  If <Esc> is mapped,
      " that sequence is not recognized as function key.  To avoid this
      " behavior :map <Esc><not-matched-key>.  But maybe this trick is
      " not best solution.
      lnoremap <buffer> <expr> <Esc> <SID>input('<Esc>')
      lnoremap <buffer> <expr> <Esc><SID>NOT-USED ""
    else
      execute printf("lnoremap <buffer> <expr> %s <SID>input('%s')", k.map, (k.map == "'") ? "''" : k.map)
    endif
  endfor
endfunction

function! s:input(key)
  if !exists("b:im_context")
    let opt_method = s:name . "_method"
    let opt_lang = s:name . "_lang"
    let method = get(b:, opt_method, get(g:, opt_method, ""))
    let lang = get(b:, opt_lang, get(g:, opt_lang, ""))
    try
      call s:im.init()
      let b:im_context = s:im.get_context(method, lang)
    catch
      echoerr v:exception
      return a:key
    endtry
  endif
  let res = b:im_context.input(a:key, 0)
  let b:keymap_name = b:im_context.status_label
  return res
endfunction

function! s:OnBufEnter()
  if &l:keymap == s:name && exists("b:im_context")
    let b:keymap_name = b:im_context.status_label
  endif
endfunction

function! s:OnBufLeave()
  if &l:keymap == s:name
    let b:keymap_name = s:name
  endif
endfunction

call s:install_key_mapping()

let &cpo = s:cpo_save

