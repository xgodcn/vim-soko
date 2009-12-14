let &runtimepath = join(split(&rtp, ',') + split(globpath(&rtp, 'plugins/*/'), '\n'), ',')
set encoding=utf-8
set termencoding=default
set fileencodings=ucs-bom,utf-8,euc-jp,cp932
set ambiwidth=double
let &backupdir = fnamemodify(finddir('backup', &runtimepath), ':p:~')
let &directory = fnamemodify(finddir('swapfile', &runtimepath), ':p:~')
let &backup = isdirectory(&backupdir)
let &writebackup = isdirectory(&backupdir)
let &swapfile = isdirectory(&directory)
set history=100               " keep 100 lines of command line history
set ignorecase smartcase
set incsearch                 " do incremental searching
set hlsearch
set grepprg=internal
set list listchars=tab:>-,trail:-
set showcmd
set cmdheight=2
set laststatus=2
set wildmenu
let &statusline = "%f %m%r%y"
      \ . "%{&bomb ? '[bomb]' : ''}"
      \ . "[%{&fenc!='' ? &fenc : &enc}]"
      \ . "[%{&ff}]"
      \ . "%#Error#%{exists('g:_qf') ? '[G:'.g:_qf.']' : ''}%*"
      \ . "%#Error#%{exists('w:_loc') ? '[L:'.w:_loc.']' : ''}%*"
      \ . "%=%v %l/%L"
set winminheight=0
set noequalalways
set backspace=indent,eol,start
set textwidth=72
set formatoptions+=nmB fo-=t fo-=c
set autoindent
set shiftwidth=2 softtabstop=2 expandtab
set cinoptions=t0,:0,g0
set tags+=./tags;
set guioptions-=t             " disable tearoff menu
set iminsert=0 imsearch=0     " turn off IM in default
set mouse=a                   " enable mouse for all
set mousemodel=popup

vnoremap * "9y/<C-R>='\V'.substitute(escape(@9,'\/'),'\n','\\n','g')<CR><CR>
inoremap <expr> <Leader>date strftime("%Y-%m-%d")
inoremap <script> <S-Tab> <SID>ExpandTab<Tab><SID>ExpandTab
inoremap <expr> <SID>ExpandTab <SID>ExpandTab()
nmap mm <Plug>MarkerToggle
vmap m  <Plug>MarkerToggle

command! -range -register -bang Number call s:Number(<line1>, <line2>, "<reg>", "<bang>")

function s:qf_update()
  let g:_qf = len(getqflist())
  if g:_qf == 0
    unlet g:_qf
  endif
  let w:_loc = len(getloclist(0))
  if w:_loc == 0
    unlet w:_loc
  endif
endfunction

augroup statusline
  autocmd QuickFixCmdPost,WinEnter * call s:qf_update()
augroup END

function s:ExpandTab()
  setl expandtab!
  return ""
endfunction

function s:Number(first, last, reg, bang)
  if a:bang == ""
    let list_save = &l:list
    setl nolist
  endif
  redir => str
  execute printf("%d,%dnumber", a:first, a:last)
  redir END
  if a:bang == ""
    let &l:list = list_save
  endif
  let str = substitute(str, '^\n\|\s\+\ze\n', '', 'g')
  call setreg(a:reg, str, "V")
endfunction

function s:MinWindow(threshold)
  " don't close completion preview window
  if mode() == 'n' && winheight(winnr('#')) <= a:threshold
    execute winnr('#') . 'resize 0'
  endif
endfunction

augroup vimrcEx
  au!

  " When editing a file, always jump to the last known cursor position.
  " Don't do it when the position is invalid or when inside an event handler
  " (happens when dropping a file on gvim).
  " Also don't do it when the mark is in the first line, that is the default
  " position when opening a file.
  autocmd BufReadPost *
        \ if line("'\"") > 1 && line("'\"") <= line("$") |
        \   exe "normal! g`\"" |
        \ endif

  " shut up beep.  t_vb should be set after GUI init
  autocmd VimEnter * set visualbell t_vb=
  " highlight for Input Method mode
  autocmd ColorScheme * hi CursorIM guibg=purple
  " weaken special chars
  autocmd ColorScheme * hi SpecialKey guifg=gray
  " shortcut to file's directory
  autocmd BufEnter * let $w = expand("%:p:h")
  " minimize window
  autocmd WinEnter * call s:MinWindow(3)
  " close completion preview window
  autocmd InsertLeave,CursorMovedI * if pumvisible() == 0 | pclose | endif
augroup END

augroup filetypeplugin
  autocmd FileType * setl sw< sts< ts< et< tw< fo<
augroup END

colorscheme delek
syntax on
filetype plugin indent on

augroup filetypeplugin
  autocmd FileType c,cpp,java,python,php,perl setl sw=4 sts=4 et
augroup END

augroup filetypeindent
  autocmd FileType html,xhtml,xml,java setl indentexpr=
  autocmd FileType php setl autoindent indentkeys-==<?
  autocmd FileType javascript setl nocindent smartindent
augroup END

augroup syntax
augroup END

augroup filetypeplugin
  autocmd FileType * au! Lint * <buffer>
  if executable('splint')
    autocmd FileType c compiler splint
          \ | let &l:makeprg = 'splint +quiet %'
          \ | autocmd Lint BufWritePost <buffer> call s:Lint()
  endif
  if executable('php')
    autocmd FileType php compiler php
          \ | let &l:makeprg = 'php -d short_open_tag=0 -d asp_tags=1 -lq %'
          \ | autocmd Lint BufWritePost <buffer> call s:Lint()
  endif
augroup END

augroup Lint
  " touch
augroup END

function s:Lint()
  silent lmake!
  redraw!
  call setloclist(0, filter(getloclist(0), 'v:val.valid'), 'r')
  call s:qf_update()
endfunction

let g:php_noShortTags = 1
let g:php_asp_tags = 1

runtime macros/matchit.vim
