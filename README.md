# pair_bracket

## 概要

(), [], {} といった括弧や ", ' といった引用符やスペースをペアで入力/削除する

![動作例](pair_bracket.gif)

この種のプラグインは数多く有るが次が不満だったので作成

* 全角に対応していない
* CmdlineLeave が働いてしまう

### 動作規則

* 括弧は
  * 開き括弧ならカーソル前後に対応した閉じ括弧がなければペア入力
  * 閉じ括弧ならカーソル直後が同じ閉じ括弧で、カーソル前に対応する開き括弧も有ればカーソル移動し、無ければ閉じ括弧を入力
  * ただしどちらも正確な対応ではなく個数だけで確認
* 前後が括弧ならば &lt;Space&gt; もペアで入力/削除
* 前後が括弧ならば &lt;CR&gt; は括弧の間に空行作成
* 引用符は
  * "Alice's Wonderland" といった入力も素直に入力できるように直前がアルファベット、数字、奇数個の \ のときはペアで入力しない<br>
  (英字以外のアルファベットはかなり適当)
  * Python の文字列 ''' 'string' ''' や TeX の数式 $$F=ma$$ を入力しやすいように直前が連続する同一記号なら直後がペアとなる個数分の引用符を入力
  * そうでなければ、閉じ括弧と同じくタイプと同じ引用符ならカーソル移動
* &lt;BS&gt; はペアで括弧、引用符を削除
  * 前後が括弧ならば間のスペースもペアで削除

## 要件

Vim version 9.0 以上

Vim9 script で書かれているので、version 8.0 以前や NeoVim では動作しない

## インストール

使用しているパッケージ・マネージャに従えば良い

### [Vundle](https://github.com/gmarik/vundle)

````vim
Plug 'iranoan/pair_bracket'
````

### [Vim-Plug](https://github.com/junegunn/vim-plug)

````vim
Plug 'iranoan/pair_bracket'
````

### [NeoBundle](https://github.com/Shougo/neobundle.vim)

````vim
NeoBundle 'iranoan/pair_bracket'
````

### [dein.nvim](https://github.com/Shougo/dein.vim)

````vim
call dein#add('iranoan/pair_bracket')
````

### Vim packadd

````sh
$ git clone https://github.com/iranoan/pair_bracket ~/.vim/pack/iranoan/start/pair_bracket
````
