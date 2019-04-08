#!/bin/bash
#set -eux
#==================================================================================================
#
# SMTPでのメール送信
#
# 概要
#   SMTPでメールを送信します。デフォルトは text/html 形式です。
#
# 引数
#   1: メール受信者リスト（カンマ区切り）
#   2: メールタイトル
#   3: メール本文
#
# サンプル
#   ./smtp_client.sh \
#     "user1@domain.local, user2@domain.local" \
#     "メール送信テスト" \
#     "$(cat ./mail_content.html)"
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 依存チェック
#--------------------------------------------------------------------------------------------------
if [[ "$(which nc)x" == "x" ]]; then echo "ns is required." >&2; exit 1; fi

#--------------------------------------------------------------------------------------------------
# 環境設定
#--------------------------------------------------------------------------------------------------
readonly SMTP_HOST="${SMTP_CLIENT__SMTP_HOST:?}"
readonly SMTP_PORT="${SMTP_CLIENT__SMTP_PORT:-25}"
readonly FROM_ADDR="${SMTP_CLIENT__FROM_ADDR:-smtp_client@domain.local}"
readonly IS_HTML="${SMTP_CLIENT__IS_HTML:-true}"
readonly SESSION_TIMEOUT="${SMTP_CLIENT_SESSION_TIMEOUT:-3}"
readonly SESSION_WAIT_TIME="${SMTP_CLIENT__SESSION_WAIT_TIME:-0.1}"

#--------------------------------------------------------------------------------------------------
# 引数チェック
#--------------------------------------------------------------------------------------------------
# メール受信者リスト（カンマ区切り）
readonly recipients="${1:?}"
# メールタイトル
readonly title="${2:?}"
# メール本文
readonly content="${3:?}"


#--------------------------------------------------------------------------------------------------
# メール受信者配列（スペース区切り）
#--------------------------------------------------------------------------------------------------
function private.recipient_array() {
  echo "${recipients}" | sed -E 's| +||g' | tr ',' ' '
  return 0
}

#--------------------------------------------------------------------------------------------------
# メールアドレスチェック
#--------------------------------------------------------------------------------------------------
function private.is_valid_address() {
  local _target_addr="${1:?}"
  if [[ $(echo "${_target_addr}" | grep -E '^[a-zA-Z0-9_\.\-]+?@[A-Za-z0-9_\.\-]+$') ]]; then
    echo "true"
    return 0
  fi

  echo "false"
  return 0
}

#--------------------------------------------------------------------------------------------------
# メール受信者リストの一括メールアドレスチェック
#--------------------------------------------------------------------------------------------------
function private.is_valid_recipients() {
  for recipient in $(private.recipient_array); do
    if [[ "${recipient}x" == "x" ]]; then continue; fi
    if [[ $(private.is_valid_address "${recipient}") != "true" ]]; then
      echo "INVALID MAIL ADDRESS: ${recipient}" >&2
      return 1
    fi
  done
  return 0
}

#--------------------------------------------------------------------------------------------------
# SMTPセッション
#--------------------------------------------------------------------------------------------------
function private.smtp_session() {
  # SMTPセッション開始
  echo "EHLO $(hostname)"
  sleep ${SESSION_WAIT_TIME}

  # 送受信情報
  echo "mail from: ${FROM_ADDR}"
  for recipient in $(private.recipient_array); do
    if [[ "${recipient}x" == "x" ]]; then continue; fi
    echo "rcpt to: ${recipient}"
  done

  # リクエストデータ開始
  echo "data"
  sleep ${SESSION_WAIT_TIME}
  # リクエストデータ.header
  echo "To: ${recipients}"
  echo "From: ${FROM_ADDR}"
  echo "Subject: ${title}"
  if [[ "${IS_HTML}" == "true" ]]; then echo "Content-Type: text/html; charset=\"UTF-8\""; fi
  echo ""
  # リクエストデータ.body
  if [[ "${IS_HTML}" == "true" ]]; then echo "<html><body>"; fi
  echo "${content}"
  if [[ "${IS_HTML}" == "true" ]]; then echo "</body></html>"; fi
  # リクエストデータ終了
  echo "."

  # SMTPセッション終了
  echo "quit"
}


#--------------------------------------------------------------------------------------------------
# 主処理
#--------------------------------------------------------------------------------------------------
# 疎通確認
( nc -vz "${SMTP_HOST}" "${SMTP_PORT}" >/dev/null ) &
check_pid=$!

SECOND=0
LIMIT=5
while [ ${SECOND} -lt ${LIMIT} ]; do
  ps ${check_pid} > /dev/null
  if [ $? -ne 0 ]; then
    break;
  fi
  SECOND=$((SECOND + 1))
  sleep 1
done
if [ ${SECOND} -ge ${LIMIT} ]; then
  # kill
  kill ${check_pid}
  echo "connection timeout"
  exit 6
fi

# メール受信者リストの一括メールアドレスチェック
private.is_valid_recipients
ret_code=$?
if [[ ${ret_code} -ne 0 ]]; then exit ${ret_code}; fi

# SMTP通信
private.smtp_session | nc -w ${SESSION_TIMEOUT} "${SMTP_HOST}" "${SMTP_PORT}" >&2
ret_code=$?
if [[ ${ret_code} -ne 0 ]]; then echo "error occured in smtp request."; fi
exit ${ret_code}

