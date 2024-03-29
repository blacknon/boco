#!/bin/bash
# Copyright(c) 2019 Blacknon. All rights reserved.
# Use of this source code is governed by an MIT license
# that can be found in the LICENSE file.

# @AUTHOR:
#    Blacknon(blacknon@orebibou.com)
# @NOTE:
#    Incremental search tool implemented with Bash function.
# @TODO:
#    - 出力行の検索、絞り込み機能の追加
#    　- 正規表現での検索機能
#    　- Ctrl+Rで切り替えできるようにする
#    - 行表示の処理を、最低限の画面更新にしてパフォーマンスを改善する
#    - バッファを挟んで、リアルタイムで出力が追加されても対応できるようにする
#    - optionでTabで下移動モード(非複数選択モード)への切り替えを行えるようにする
#      - 参考url(completeができるようにする)
#        - https://github.com/pindexis/qfc/blob/master/bin/qfc.sh

## ----------
# function
## ----------
boco() {
  ## ----------
  # variable
  ## ----------
  # ANSI Escape(Color)
  local -r COLOR_NONE=$'\E[0m'
  local -r COLOR_RED=$'\E[0;31m'
  local -r COLOR_GREEN=$'\E[0;32m'
  local -r COLOR_ORANGE=$'\E[0;33m'
  local -r COLOR_BLUE=$'\E[0;34m'
  local -r COLOR_PURPLE=$'\E[0;35m'
  local -r COLOR_CYAN=$'\E[0;36m'
  local -r COLOR_LGRAY=$'\E[0;37m'
  local -r COLOR_BACK_RED=$'\E[41m'
  local -r COLOR_BACK_GREEN=$'\E[42m'
  local -r COLOR_BACK_ORANGE=$'\E[43m'
  local -r COLOR_BACK_BLUE=$'\E[44m'
  local -r COLOR_BACK_PURPLE=$'\E[45m'
  local -r COLOR_BACK_CYAN=$'\E[46m'
  local -r COLOR_BACK_GRAY=$'\E[47m'

  # ANSI Escape(Other)
  local -r CURSOR_GET=$'\E[6n'
  local GREP_CLEAR=$'\E[m\E[K'

  # local use variables
  local input           # input key code
  local tmp             # input key code(2nd)
  local data            # Get stdin or file data
  local array           # data to Array(Original)
  local view_array      # data to Array(Refine data)
  local now_cursor_line # Now cursor position in terminal(line)
  local now_list_line   # now cursor line (in boco list)
  local selected_line   # now selected line (in boco list. array)
  local max_line        # VIEW_ARRAY_max_line
  local view_max_line   # max line in terminal
  local scroll_position # boco list scroll position (1st line)
  local surplus_line

  # option
  local flg_p
  local search_word

  # env
  local -r OLD_IFS=${IFS}

  # cmd
  local cmd_grep

  ## ----------
  # getopts
  ## ----------
  __boco_usage() {
    echo "usage:"
    echo " -p               ... not print control character"
    echo " -q {search_word} ... search word"
    return 1
  }

  while getopts :pq: OPT; do
    case ${OPT} in
    p) flg_p="TRUE" ;;
    q) search_word="${OPTARG}" ;;
    : | \?)
      __boco_usage
      return 1
      ;;
    esac
  done
  shift $((OPTIND - 1))

  ## ----------
  # shopt/setopt
  ## ----------
  # set shopt(get windows size.)
  case "${SHELL##*/}" in
  bash*)
    shopt -s checkwinsize
    (
      :
      :
    )
    ;;
  zsh*) setopt localoptions ksharrays ;;
  esac

  ## ----------
  # function
  ## ----------
  # @brief:
  #     get now cursor positon in terminal.
  # @return: now_cursor_line
  __get_cursor_position() {
    # variable
    local old_stty
    local cursor

    # move tty
    exec </dev/tty
    old_stty=$(stty -g)
    stty raw -echo min 0

    # get position data
    printf "${CURSOR_GET}" >/dev/tty

    case "${SHELL##*/}" in
    bash*) IFS=';' read -r -d R -a cursor ;;
    zsh*) IFS=';' read -s -d R cursor ;;
    esac

    IFS=$'\n'
    stty "${old_stty}"

    cursor="${cursor##*\[}"
    cursor="${cursor%;*}"

    now_cursor_line=${cursor}
  }

  # @brief: print data line with ANSI escape code.
  #     __print_line_position
  #          ${1} ... add_line
  #          ${2} ... cursor_line_type(0(current line)|1(selected line)|2(other))
  #          ${3} ... print_data
  __print_line_position() {
    # variable
    local add_line
    local cursor_line_flag
    local print_line
    local print_data

    add_line=${1}
    cursor_line_type=${2}
    print_line=$((${now_cursor_line} + ${add_line}))
    line="${3}"
    print_data=${line#*:}

    # move cursor
    printf "\e["${print_line}";0H" >&2

    # print line
    if [[ ${cursor_line_type} -eq 0 ]]; then
      print_data="${print_data//$(echo ${GREP_CLEAR})/$(echo ${GREP_CLEAR}${COLOR_YELLOW}${COLOR_BACK_BLUE})}"
      printf "${COLOR_YELLOW}${COLOR_BACK_BLUE}"'%s'"${COLOR_NONE}\n" "${print_data}" >&2

    elif [[ ${cursor_line_type} -eq 1 ]]; then
      print_data="${print_data//$(echo ${GREP_CLEAR})/$(echo ${GREP_CLEAR}${COLOR_YELLOW}${COLOR_BACK_GREEN})}"
      printf "${COLOR_YELLOW}${COLOR_BACK_GREEN}"'%s'"${COLOR_NONE}\n" "${print_data}" >&2
    else
      printf "%s\n" "${print_data}" >&2
    fi
  }

  # @brief:
  #     __print_data
  __print_data() {
    # variable
    local header_text
    local header_text_count
    local list_range_max
    local list_range_min
    local list_text

    # move cursor
    printf "\e[${now_cursor_line};0H" >&2

    # print header
    header_text="QUERY: ${search_word} "
    header_text_count=${#header_text}
    printf "${header_text}\n" >&2

    # print line
    list_range_max=$((${scroll_position} + ${view_max_line}))

    local x=0
    for ((i = ${scroll_position}; i < ${list_range_max}; i++)); do
      # テキストを変数に代入
      list_line="${view_array_data[${i}]}"

      if [[ ${now_list_line} -eq ${i} ]]; then
        # print now select line
        __print_line_position $((${x} + 1)) 0 "${list_line}"
      elif [[ $(__selected_check_in ${list_line%%:*}) -eq 0 ]]; then
        # print selected line
        __print_line_position $((${x} + 1)) 1 "${list_line}"
      else
        # print other line
        __print_line_position $((${x} + 1)) 2 "${list_line}"
      fi
      x=$((${x} + 1))
    done

    # cursor move to header
    printf "\e[${now_cursor_line};${header_text_count}H" >&2
  }

  # @brief:
  #     clear printed data
  __clear_print_data() {
    # move cursor
    printf "\e[${now_cursor_line};0H" >&2

    # clear line
    echo $'\e[2K'$'\e[1A' >&2

    for ((i = 0; i < ${view_max_line}; i++)); do
      # move cursor 1 down
      echo $'\e[1B' >&2

      # clear line
      echo $'\e[1A'$'\e[1G'$'\e[2K'$'\e[1A' >&2
    done

    # move cursor
    printf "\e[${now_cursor_line};0H" >&2
  }

  # @brief:
  #     update view array data.
  __update_view_array() {
    case "${SHELL##*/}" in
    bash*)
      shopt -s checkwinsize
      (
        :
        :
      )
      ;;
    zsh*) setopt localoptions ksharrays ;;
    esac
    local search_word_count
    local array_str
    local view_array_str
    local search_word_array
    local for_count

    local IFS=$'\n'
    search_word_count=${#search_word}

    # clear view_array_data
    view_array_data=()
    array_str="$(
      IFS=$'\n'
      echo "${array_data[*]}"
    )"

    # grep data
    if [[ ${search_word_count} -gt 0 ]]; then
      # split string at space
      case "${SHELL##*/}" in
      bash*) IFS=" " read -r -a search_word_array <<<"${search_word}" ;;
      zsh*) IFS=" " read -r -A search_word_array <<<"${search_word}" ;;
      esac

      IFS=$'\n'
      view_array_str="${array_str}"

      for_count=0
      for word in ${search_word_array[*]}; do
        if [[ ${for_count} -eq 0 ]]; then
          # with number
          view_array_str="$(echo "${view_array_str}" | GREP_COLORS='ln=:se=' \grep -a -F -n --color=always -i -- ${word})"
        else
          # without number
          view_array_str="$(echo "${view_array_str}" | GREP_COLORS='ln=:se=' \grep -a -F --color=always -i -- ${word})"
        fi
        for_count=$((for_count + 1))
      done
    else
      # use regex
      view_array_str="$(echo "${array_str}" | GREP_COLORS='ln=:se=' \grep -a -n -E '.*')"
    fi

    # set view_array_data
    view_array_data=($(echo "${view_array_str}"))
    local IFS=${OLD_IFS}
  }

  # @brief: update max_line
  __update_max_line() {
    # set max_line
    max_line="${#view_array_data[@]}"
    view_max_line=${max_line}

    # ターミナルの残り行数を見ていたが、固定にするためコメントアウト
    # surplus_line=$((${terminal_lines} - ${now_cursor_line}))
    # if [ surplus_line <= (terminal_lines/2) ]
    # if [[ ${surplus_line} -le $((${terminal_lines} / 2)) ]];then
    #   surplus_line=$((${terminal_lines} / 2))
    # fi

    # 出力行数(20で固定)
    surplus_line=20

    if [[ ${surplus_line} -le ${view_max_line} ]]; then
      view_max_line="${surplus_line}"
    fi

    if [[ $((${terminal_lines} - ${view_max_line})) -le ${now_cursor_line} ]]; then
      now_cursor_line=$((${terminal_lines} - ${view_max_line}))
    fi

    if [[ ${max_line} -le ${scroll_position} ]]; then
      scroll_position=$((${max_line} - 1))

      if [[ ${scroll_position} -lt 0 ]]; then
        scroll_position=0
      fi
    fi

    if [[ ${now_list_line} -ge $((${view_max_line})) ]]; then
      now_list_line=$((${view_max_line} - 1))
    fi

    for ((i = 0; i < ${view_max_line}; i++)); do
      echo "" >&2
    done

    printf "\e[${now_cursor_line};0H" >&2
  }

  # @brief: scroll up function
  __scroll_up() {
    now_list_line=$((${now_list_line} - 1))
    if [[ ${now_list_line} -lt 0 ]]; then
      now_list_line=0
      return
    fi

    # scroll up
    list_range_min=${scroll_position}
    if [[ ${now_list_line} -lt ${list_range_min} ]]; then
      # if scroll up
      scroll_position=$((${scroll_position} - 1))

      if [[ ${scroll_position} -lt 0 ]]; then
        scroll_position=0
      fi

      __clear_print_data
      __print_data

    else
      local header_text
      local header_text_count
      local term_line
      local unselect_line

      header_text="QUERY: ${search_word} "
      header_text_count=${#header_text}

      term_line=$((${now_list_line} - ${scroll_position}))

      # unselect line
      unselect_line="${view_array_data[$((${now_list_line} + 1))]}"
      if [[ $(__selected_check_in ${unselect_line%%:*}) -eq 0 ]]; then
        __print_line_position $((${term_line} + 2)) 1 "${view_array_data[$((${now_list_line} + 1))]}"
      else
        __print_line_position $((${term_line} + 2)) 2 "${view_array_data[$((${now_list_line} + 1))]}"
      fi

      # select line
      __print_line_position $((${term_line} + 1)) 0 "${view_array_data[${now_list_line}]}"

      # move cursor
      printf "\e[${now_cursor_line};${header_text_count}H" >&2
    fi
  }

  # @brief: scroll down function
  __scroll_down() {
    now_list_line=$((${now_list_line} + 1))
    if [[ ${now_list_line} -gt $((${max_line} - 1)) ]]; then
      now_list_line=$((${max_line} - 1))
      return
    fi

    # scroll down
    local list_range_max=$((${scroll_position} + ${view_max_line}))
    if [[ ${now_list_line} -ge ${list_range_max} ]]; then
      # if scroll down
      scroll_position=$((${scroll_position} + 1))
      __clear_print_data
      __print_data
    else
      local header_text
      local header_text_count
      local term_line
      local unselect_line

      header_text="QUERY: ${search_word} "
      header_text_count=${#header_text}

      term_line=$((${now_list_line} - ${scroll_position}))
      unselect_line="${view_array_data[$((${now_list_line} - 1))]}"

      # unselect line
      if [[ $(__selected_check_in ${unselect_line%%:*}) -eq 0 ]]; then
        __print_line_position ${term_line} 1 "${view_array_data[$((${now_list_line} - 1))]}"
      else
        __print_line_position ${term_line} 2 "${view_array_data[$((${now_list_line} - 1))]}"
      fi

      # select line
      __print_line_position "$((${term_line} + 1))" 0 "${view_array_data[${now_list_line}]}"

      # move cursor
      printf "\e[${now_cursor_line};${header_text_count}H" >&2
    fi
  }

  # @brief: trap ctrl + c
  __trap_2() {
    __clear_print_data
    local IFS=${OLD_IFS}
    return 1
  }

  # @brief:
  #     check if number is included in array
  __selected_check_in() {
    for e in ${selected_line[@]}; do
      if [[ ${e} -eq ${1} ]]; then
        echo 0
        return
      fi
    done

    echo 1
  }

  # @brief: Add element to selected_line
  __selected_add() {
    selected_line=(${selected_line[@]} $1)
  }

  # @brief: Delete element to selected_line
  __selected_del() {
    local new_selected_line=()
    for e in ${selected_line[@]}; do
      if [[ ! ${e} -eq ${1} ]]; then
        new_selected_line=(${new_selected_line[@]} ${e})
      fi
    done

    selected_line=(${new_selected_line[@]})
  }

  ## ----------
  # main
  ## ----------
  # set trap
  trap '__trap_2;trap - 2;return 1;' 2

  # check -p option
  if [[ "${flg_p}" != "TRUE" ]]; then
    printf '\033[?7l'
  fi

  # get data from stdin or file.
  if [ -p /dev/stdin ]; then
    data="$(</dev/stdin)"
  else
    data="$(<$@)"
  fi

  # data to Array
  local IFS=$'\n'
  local array_data=($(echo "${data}"))
  local IFS=${OLD_IFS}

  # get cursor positon
  __get_cursor_position

  # get terminal size
  local terminal_lines=$((${LINES} - 1))
  local terminal_columns=$((${COLUMNS} - 1))

  # update view_array
  __update_view_array

  # set max_line & VIEW_max_line
  __update_max_line

  # set now_list_line, selected_line
  now_list_line=0
  scroll_position=0
  selected_line=()

  # first print out
  __print_data

  # get input key loop
  local IFS=$'\n'
  while true; do
    # get input key
    case "${SHELL##*/}" in
    bash*) read -rsn1 input </dev/tty ;;
    zsh*) read -r -s -k 1 input </dev/tty ;;
    esac

    case "${input}" in
    # hundling Escape(\x1B)
    $'\x1B')
      case "${SHELL##*/}" in
      bash*) read -rsn1 -t 0.1 tmp </dev/tty ;;
      zsh*) read -r -s -k 1 -t 0.1 tmp </dev/tty ;;
      esac

      if [[ "${tmp}" == "[" ]]; then
        case "${SHELL##*/}" in
        bash*) read -rsn1 -t 0.1 tmp </dev/tty ;;
        zsh*) read -r -s -k 1 -t 0.1 tmp </dev/tty ;;
        esac

        case "${tmp}" in
        # up key
        "A") __scroll_up ;;
          # down key
        "B") __scroll_down ;;
        esac
      fi

      # Flush "stdin" with 0.1  sec timeout.
      case "${SHELL##*/}" in
      bash*) read -r -n 5 -t 0.1 ;;
      zsh*) read -r -k 5 -t 0.1 ;;
      esac

      ;;

      # Delete(Backspace(\x7F)) key
    $'\x7F')
      # get search word count
      local search_word_count=${#search_word}

      # 検索ワードの文字数が0より大きい場合、文字を削除して表示を更新する
      if [[ ${search_word_count} -gt 0 ]]; then
        local search_word_count=$((${search_word_count} - 1))
        local search_word=${search_word:0:${search_word_count}}

        __update_view_array
        __clear_print_data
        __update_max_line
        __print_data
      fi
      ;;

      # input Space Key
    " ")
      search_word=${search_word}${input}
      __update_view_array
      __clear_print_data
      __update_max_line
      __print_data
      ;;

      # input Tab key(\x09)
      # Toggle multi select.
    $'\x09')
      # add selected line
      local line="${view_array_data[${now_list_line}]}"
      if [[ $(__selected_check_in ${line%%:*}) -eq 0 ]]; then
        __selected_del ${line%%:*}
      else
        __selected_add ${line%%:*}
      fi
      __clear_print_data
      __update_max_line
      __print_data
      ;;

      # input Ctrl + A key
      # Selected all view lines.

      # input Ctrl + R key
      # Toggle grep mode(plane <-> regex).
      # $'\cr')
      #   __clear_print_data
      #   echo "Ctrl + R"
      #   break
      #   ;;

      # input Enter key
    "" | $'\n')
      __clear_print_data
      local new_selected_line

      if [[ ${#selected_line} -eq 0 ]]; then
        local line="${view_array_data[${now_list_line}]}"
        selected_line=(${line%%:*})
      fi

      IFS=$'\n' new_selected_line=($(sort -n <<<"${selected_line[*]}"))
      for NO in ${new_selected_line[@]}; do
        echo "${array_data[$((${NO} - 1))]}"
      done
      break
      ;;

    # other key
    *)
      search_word=${search_word}${input}
      __update_view_array
      __clear_print_data
      __update_max_line
      __print_data
      ;;
    esac
  done

  # check -p option
  if [[ "${flg_p}" != "TRUE" ]]; then
    printf '\033[?7h'
  fi

  local IFS=${OLD_IFS}
}
