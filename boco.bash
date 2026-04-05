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

  local use_perf_mode
  local rendered_line_count=0
  local prev_search_word
  local prev_search_word_lower_array=()

  ## ----------
  # getopts
  ## ----------
  __boco_usage() {
    printf '%s\n' "usage:"
    printf '%s\n' " -p               ... not print control character"
    printf '%s\n' " -q {search_word} ... search word"
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
    shopt -s nocasematch
    (
      :
      :
    )
    ;;
  zsh*) setopt localoptions ksharrays nocasematch ;;
  esac

  if [[ -n "${BOCO_PERFORMANCE_MODE}" ]]; then
    use_perf_mode="${BOCO_PERFORMANCE_MODE}"
  elif [[ -n "${SSH_CONNECTION}" || -n "${SSH_CLIENT}" || -n "${SSH_TTY}" ]]; then
    use_perf_mode=1
  else
    use_perf_mode=0
  fi

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
      printf "${COLOR_YELLOW}${COLOR_BACK_BLUE}"'%s'"${COLOR_NONE}\n" "${print_data}" >&2

    elif [[ ${cursor_line_type} -eq 1 ]]; then
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
    local list_line
    local print_data
    local cursor_line_type
    local output
    local clear_count

    # move cursor
    header_text="QUERY: ${search_word} "
    header_text_count=${#header_text}
    output=$'\e['"${now_cursor_line}"';0H'
    output+=$'\e[2K'"${header_text}"$'\n'

    # print line
    list_range_max=$((${scroll_position} + ${view_max_line}))

    local x=0
    for ((i = ${scroll_position}; i < ${list_range_max}; i++)); do
      list_line="${view_array_data[${i}]}"
      print_data=${list_line#*:}

      if [[ ${now_list_line} -eq ${i} ]]; then
        cursor_line_type=0
      elif __selected_check_in "${list_line%%:*}"; then
        cursor_line_type=1
      else
        cursor_line_type=2
      fi

      output+=$'\e[2K'
      if [[ ${cursor_line_type} -eq 0 ]]; then
        output+="${COLOR_YELLOW}${COLOR_BACK_BLUE}${print_data}${COLOR_NONE}"
      elif [[ ${cursor_line_type} -eq 1 ]]; then
        output+="${COLOR_YELLOW}${COLOR_BACK_GREEN}${print_data}${COLOR_NONE}"
      else
        output+="${print_data}"
      fi
      output+=$'\n'
      x=$((${x} + 1))
    done

    clear_count=$((${rendered_line_count} - ${view_max_line}))
    for ((i = 0; i < ${clear_count}; i++)); do
      output+=$'\e[2K\n'
    done

    # cursor move to header
    output+=$'\e['"${now_cursor_line}"';'"${header_text_count}"'H'
    printf '%s' "${output}" >&2
    rendered_line_count=${view_max_line}
  }

  # @brief:
  #     escape glob pattern chars for fixed-string matching.
  __escape_glob() {
    local escaped=${1//\\/\\\\}
    escaped=${escaped//\*/\\*}
    escaped=${escaped//\?/\\?}
    escaped=${escaped//\[/\\[}
    escaped=${escaped//\]/\\]}
    printf '%s' "${escaped}"
  }

  # @brief:
  #     convert input string to lower case.
  __to_lower() {
    case "${SHELL##*/}" in
    bash*) printf '%s' "${1,,}" ;;
    zsh*) printf '%s' "${1:l}" ;;
    *) printf '%s' "${1}" ;;
    esac
  }

  # @brief:
  #     clear printed data
  __clear_print_data() {
    local output

    # move cursor
    output=$'\e['"${now_cursor_line}"';0H'
    output+=$'\e[2K'

    for ((i = 0; i < ${rendered_line_count}; i++)); do
      output+=$'\e[1B\e[2K'
    done

    # move cursor
    output+=$'\e['"${now_cursor_line}"';0H'
    printf '%s' "${output}" >&2
    rendered_line_count=0
  }

  # @brief:
  #     update view array data.
  __update_view_array() {
    local line
    local line_no
    local source_line_no
    local source_indices
    local prev_view_array_index_data
    local lower_search_word
    local search_word_lower_array
    local search_word_pattern_array
    local matched
    local word
    local idx
    local start_index=0
    local can_refine_from_prev=0

    prev_view_array_index_data=("${view_array_index_data[@]}")

    # clear view_array_data
    view_array_data=()
    view_array_index_data=()

    lower_search_word=$(__to_lower "${search_word}")

    if [[ -n "${search_word}" ]]; then
      case "${SHELL##*/}" in
      bash*) IFS=" " read -r -a search_word_lower_array <<<"${lower_search_word}" ;;
      zsh*) IFS=" " read -r -A search_word_lower_array <<<"${lower_search_word}" ;;
      esac
    else
      search_word_lower_array=()
    fi

    for word in "${search_word_lower_array[@]}"; do
      [[ -z "${word}" ]] && continue
      search_word_pattern_array+=("$(__escape_glob "${word}")")
    done

    if [[ -n "${prev_search_word}" && -n "${search_word}" && "${search_word}" == "${prev_search_word}"* ]]; then
      if [[ ${#search_word_pattern_array[@]} -eq ${#prev_search_word_lower_array[@]} && ${#search_word_pattern_array[@]} -gt 0 ]]; then
        can_refine_from_prev=1

        for ((idx = 0; idx < ${#prev_search_word_lower_array[@]} - 1; idx++)); do
          if [[ "${search_word_lower_array[${idx}]}" != "${prev_search_word_lower_array[${idx}]}" ]]; then
            can_refine_from_prev=0
            break
          fi
        done

        if [[ ${can_refine_from_prev} -eq 1 ]]; then
          idx=$((${#search_word_pattern_array[@]} - 1))
          if [[ "${search_word_lower_array[${idx}]}" == "${prev_search_word_lower_array[${idx}]}"* ]]; then
            start_index=${idx}
            source_indices=("${prev_view_array_index_data[@]}")
          else
            can_refine_from_prev=0
          fi
        fi
      fi

      if [[ ${can_refine_from_prev} -eq 0 ]]; then
        source_indices=("${prev_view_array_index_data[@]}")
      fi
    else
      source_indices=("${array_index_data[@]}")
    fi

    for source_line_no in "${source_indices[@]}"; do
      line_no=${source_line_no}
      line="${array_data[${line_no}]}"
      matched=1

      for ((idx = ${start_index}; idx < ${#search_word_pattern_array[@]}; idx++)); do
        if [[ "${array_data_lower[${line_no}]}" != *"${search_word_pattern_array[${idx}]}"* ]]; then
          matched=0
          break
        fi
      done

      if [[ ${matched} -eq 1 ]]; then
        view_array_data+=("$((line_no + 1)):${line}")
        view_array_index_data+=("${line_no}")
      fi
    done

    prev_search_word=${search_word}
    prev_search_word_lower_array=("${search_word_lower_array[@]}")
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

    # 出力行数
    if [[ "${use_perf_mode}" == "1" ]]; then
      surplus_line=12
    else
      surplus_line=20
    fi

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

    if [[ ${rendered_line_count} -eq 0 ]]; then
      for ((i = 0; i < ${view_max_line}; i++)); do
        printf "\n" >&2
      done

      printf "\e[${now_cursor_line};0H" >&2
    fi
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
      if __selected_check_in "${unselect_line%%:*}"; then
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
      if __selected_check_in "${unselect_line%%:*}"; then
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
        return 0
      fi
    done

    return 1
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

  # @brief:
  #     sort selected_line numerically with shell builtins.
  __selected_sort() {
    local sorted=()
    local value
    local i
    local inserted

    for value in "${selected_line[@]}"; do
      inserted=0

      for ((i = 0; i < ${#sorted[@]}; i++)); do
        if [[ ${value} -lt ${sorted[${i}]} ]]; then
          sorted=("${sorted[@]:0:${i}}" "${value}" "${sorted[@]:${i}}")
          inserted=1
          break
        fi
      done

      if [[ ${inserted} -eq 0 ]]; then
        sorted+=("${value}")
      fi
    done

    selected_line=("${sorted[@]}")
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
  local array_data=(${data})
  local array_data_lower=()
  local array_index_data=()
  local view_array_index_data=()
  local IFS=${OLD_IFS}

  for i in "${!array_data[@]}"; do
    array_index_data+=("${i}")
    array_data_lower+=("$(__to_lower "${array_data[${i}]}")")
  done

  prev_search_word=
  prev_search_word_lower_array=()

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
        __update_max_line
        __print_data
      fi
      ;;

      # input Space Key
    " ")
      search_word=${search_word}${input}
      __update_view_array
      __update_max_line
      __print_data
      ;;

      # input Tab key(\x09)
      # Toggle multi select.
    $'\x09')
      # add selected line
      local line="${view_array_data[${now_list_line}]}"
      if __selected_check_in "${line%%:*}"; then
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

      __selected_sort
      new_selected_line=("${selected_line[@]}")
      for NO in "${new_selected_line[@]}"; do
        printf '%s\n' "${array_data[$((${NO} - 1))]}"
      done
      break
      ;;

    # other key
    *)
      search_word=${search_word}${input}
      __update_view_array
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

# @brief:
#     history selector for Ctrl-R.
#     Uses shell builtins as much as possible to reduce remote latency.
boco_history_select() {
  local current_buffer
  local selected
  local line
  local history_lines=()

  case "${SHELL##*/}" in
  zsh*) setopt localoptions ksharrays ;;
  esac

  case "${SHELL##*/}" in
  bash*)
    local -A seen=()
    current_buffer=${READLINE_LINE}
    ;;
  zsh*)
    typeset -A seen
    current_buffer=${BUFFER}
    ;;
  *)
    current_buffer=
    ;;
  esac

  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    [[ -n "${seen["${line}"]}" ]] && continue
    seen["${line}"]=1
    history_lines+=("${line}")
  done < <(builtin fc -lnr 1)

  if [[ ${#history_lines[@]} -eq 0 ]]; then
    return 0
  fi

  selected=$(printf '%s\n' "${history_lines[@]}" | boco -p -q "${current_buffer}")

  case "${SHELL##*/}" in
  bash*)
    READLINE_LINE=${selected}
    READLINE_POINT=${#READLINE_LINE}
    ;;
  zsh*)
    BUFFER=${selected}
    CURSOR=${#BUFFER}
    zle redisplay 2>/dev/null
    ;;
  esac
}
