set encoding=utf-8
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
set statusline=%f\ %m%r%y%{_bomb()}%{_fenc()}%{_ff()}%=%v\ %l/%L
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

function _bomb()
  return &bomb ? '[bomb]' : ''
endfunction

function _fenc()
  return &fenc != '' ? '['.&fenc.']' : '['.&enc.']'
endfunction

function _ff()
  return '['.&ff.']'
endfunction

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

augroup filetypedetect
  autocmd BufRead,BufNewFile *.as           setf javascript
  autocmd BufRead,BufNewFile SConstruct     setf python
augroup END

augroup filetypeplugin
  autocmd FileType * setl sw< sts< ts< et< tw< fo<
augroup END

colorscheme delek
syntax on
filetype plugin indent on

augroup filetypeplugin
  autocmd FileType c,cpp,java,python,php setl sw=4 sts=4 et
augroup END
augroup filetypeindent
augroup END
augroup syntax
augroup END

runtime macros/matchit.vim
