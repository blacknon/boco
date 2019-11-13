boco
====

Bash Shell Function's Fuzzy Finder.

<p align="center">
<img src="./img/boco.gif" />
</p>


## Requirements

- grep
- sort

## Usage

### Simple select

Basic usage is the method of selecting from the standard input received from the pipe.

    echo {a..f}{01..03} | xargs -n3 | boco


### History select

Can make history selection like peco or fzf. Load the following function.

`TODO: $HISTTIMEFORMATの有無に応じてhistoryの加工方法を切り替える`

    __history_selection() {
      # 逆順に出力するコマンド
      if which tac >/dev/null; then
        local reverse="tac"
      else
        local reverse="tail -r"
      fi

      # 入力中の値をクエリとして渡すため、変数に代入
      case $(basename ${SHELL}) in
        zsh*)  local data="${BUFFER}" ;;
        bash*) local data="${READLINE_LINE}" ;;
      esac

      # selecterとしてbocoを指定
      local selecter="boco -p -q \"${data}\""

      # 長い行を表示させるための制御用ANSIエスケープを出力
      printf '\033[?7l'

      # shellに応じて処理を変える
      case $(basename ${SHELL}) in
        zsh*)
          BUFFER=$(history -n 1 | eval ${reverse} | awk '!a[$0]++' | eval "${selecter}") # 入力中のコマンドの内容を上書き
          CURSOR=${#BUFFER} # カーソル位置を移動
          ;;
        bash*)
          local buffer=$(history | sed -r 's/^[ 0-9]+:* *[0-9]+ [0-9]{2}:[0-9]{2}:[0-9]{2} *:* *//g' | eval ${reverse} | awk '!a[$0]++' |eval ${selecter})
          READLINE_LINE="${buffer}" # 入力中のコマンドの内容を上書き
          READLINE_POINT=${#READLINE_LINE} # カーソル位置を移動
          ;;
      esac

      printf '\033[?7h'
    }

    # Ctrl + R でのhistoryの検索を__history_selection での処理に変更する
    bind -x '"\C-r": __history_selection'

### Use by ssh connection destination

TODO: ssh接続先で使用する方法について記述する







