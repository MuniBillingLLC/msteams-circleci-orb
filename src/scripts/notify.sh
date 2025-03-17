#!/usr/bin/env bash

# shellcheck disable=SC2016,SC3043
if [[ "$MSTEAMS_PARAM_CUSTOM" == \$* ]]; then
    echo "Doing substitution custom"
    MSTEAMS_PARAM_CUSTOM="$(eval echo "${MSTEAMS_PARAM_CUSTOM}" | circleci env subst)"
fi
if [[ "$MSTEAMS_PARAM_TEMPLATE" == \$* ]]; then
    echo "Doing substitution template"
    MSTEAMS_PARAM_TEMPLATE="$(eval echo "${MSTEAMS_PARAM_TEMPLATE}" | circleci env subst)"
fi

if [ "${MSTEAMS_PARAM_DEBUG:-0}" -eq 1 ]; then
    set -x
fi

# Import utils.
eval "$MSTEAMS_SCRIPT_UTILS"
JQ_PATH=/usr/local/bin/jq

BuildMessageBody() {
    # Send message
    #   If sending message, default to custom template,
    #   if none is supplied, check for a pre-selected template value.
    #   If none, error.
    if [ -n "${MSTEAMS_PARAM_CUSTOM:-}" ]; then
        SanitizeVars "$MSTEAMS_PARAM_CUSTOM"
        ModifyCustomTemplate
        # shellcheck disable=SC2016
        CUSTOM_BODY_MODIFIED=$(echo "$CUSTOM_BODY_MODIFIED" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/`/\\`/g')
        T2="$(eval printf '%s' \""$CUSTOM_BODY_MODIFIED"\")"
    else
        # shellcheck disable=SC2154
        if [ -n "${MSTEAMS_PARAM_TEMPLATE:-}" ]; then
            TEMPLATE="\$$MSTEAMS_PARAM_TEMPLATE"
        elif [ "$CCI_STATUS" = "pass" ]; then
            TEMPLATE="\$basic_success_1"
        elif [ "$CCI_STATUS" = "fail" ]; then
            TEMPLATE="\$basic_fail_1"
        else
            echo "A template wasn't provided nor is possible to infer it based on the job status. The job status: '$CCI_STATUS' is unexpected."
            exit 1
        fi

        [ -z "${MSTEAMS_PARAM_TEMPLATE:-}" ] && echo "No message template was explicitly chosen. Based on the job status '$CCI_STATUS' the template '$TEMPLATE' will be used."
        template_body="$(eval printf '%s' \""$TEMPLATE\"")"
        SanitizeVars "$template_body"

        # shellcheck disable=SC2016
        T1="$(printf '%s' "$template_body" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/`/\\`/g')"
        T2="$(eval printf '%s' \""$T1"\")"
    fi

    MSTEAMS_MSG_BODY="$T2"
}

NotifyWithRetries() {
    local success_request=false
    local retry_count=0
    while [ "$retry_count" -le "$MSTEAMS_PARAM_RETRIES" ]; do
        if [[ "$RUNNING_BATS_TESTS" == "true" ]]; then
            echo "Skipping curl request because we are in test mode"
            MSTEAMS_SENT_RESPONSE="{}"
            success_request=true
            break
        else
            if MSTEAMS_SENT_RESPONSE=$(curl -s -f -X POST -H 'Content-type: application/json' --data "$MSTEAMS_MSG_BODY" "$MSTEAMS_WEBHOOK"); then
                echo "Notification sent"
                success_request=true
                break
            else
                echo "Error sending notification. Retrying..."
                retry_count=$((retry_count + 1))
                sleep "$MSTEAMS_PARAM_RETRY_DELAY"
            fi
        fi
    done
    if [ "$success_request" = false ]; then
        echo "Error sending notification. Max retries reached"
        exit 1
    fi
}

PostToMsTeams() {
    echo "Sending to MS Teams Webhook"
    if [ "$MSTEAMS_PARAM_DEBUG" -eq 1 ]; then
        printf "%s\n" "$MSTEAMS_MSG_BODY" >"$MSTEAMS_MSG_BODY_LOG"
        echo "The message body being sent to MS Teams can be found below. To view redacted values, rerun the job with SSH and access: ${MSTEAMS_MSG_BODY_LOG}"
        echo "$MSTEAMS_MSG_BODY"
    fi

    NotifyWithRetries

    if [ "$MSTEAMS_PARAM_DEBUG" -eq 1 ]; then
        printf "%s\n" "$MSTEAMS_SENT_RESPONSE" >"$MSTEAMS_SENT_RESPONSE_LOG"
        echo "The response from the API call to MS Teams can be found below. To view redacted values, rerun the job with SSH and access: ${MSTEAMS_SENT_RESPONSE_LOG}"
        echo "$MSTEAMS_SENT_RESPONSE"
    fi

    MSTEAMS_ERROR_MSG=$(echo "$MSTEAMS_SENT_RESPONSE" | jq '.error')
    if [ ! "$MSTEAMS_ERROR_MSG" = "null" ]; then
        if [[ "$MSTEAMS_ERROR_MSG" != "" ]]; then
            echo "MS Teams API returned an error message:"
            echo "$MSTEAMS_ERROR_MSG"
            echo
            echo
            echo "View the Setup Guide: https://support.microsoft.com/en-us/office/create-incoming-webhooks-with-workflows-for-microsoft-teams-8ae491c7-0394-4861-ba59-055e33f75498"
            if [ "$MSTEAMS_PARAM_IGNORE_ERRORS" = "0" ]; then
                exit 1
            fi
        fi
    fi
}

ModifyCustomTemplate() {
    CUSTOM_BODY_MODIFIED=$(echo "$MSTEAMS_PARAM_CUSTOM" | jq '.')
}

InstallJq() {
    echo "Checking For JQ + CURL"
    if command -v curl >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
        uname -a | grep Darwin >/dev/null 2>&1 && JQ_VERSION=jq-osx-amd64 || JQ_VERSION=jq-linux32
        curl -Ls -o "$JQ_PATH" https://github.com/stedolan/jq/releases/download/jq-1.6/"${JQ_VERSION}"
        chmod +x "$JQ_PATH"
        command -v jq >/dev/null 2>&1
        return $?
    else
        command -v curl >/dev/null 2>&1 || {
            echo >&2 "MS TEAMS ORB ERROR: CURL is required. Please install."
            exit 1
        }
        command -v jq >/dev/null 2>&1 || {
            echo >&2 "MS TEAMS ORB ERROR: JQ is required. Please install"
            exit 1
        }
        return $?
    fi
}

FilterBy() {
    if [ -z "$1" ]; then
        return
    fi
    # If any pattern supplied matches the current branch or the current tag, proceed; otherwise, exit with message.
    FLAG_MATCHES_FILTER="false"
    # shellcheck disable=SC2001
    for i in $(echo "$1" | sed "s/,/ /g"); do
        if echo "$2" | grep -Eq "^${i}$"; then
            FLAG_MATCHES_FILTER="true"
            break
        fi
    done
    # If the invert_match parameter is set, invert the match.
    if { [ "$FLAG_MATCHES_FILTER" = "false" ] && [ "$MSTEAMS_PARAM_INVERT_MATCH" -eq 0 ]; } ||
        { [ "$FLAG_MATCHES_FILTER" = "true" ] && [ "$MSTEAMS_PARAM_INVERT_MATCH" -eq 1 ]; }; then
        # dont send message.
        echo "NO MS TEAMS ALERT"
        echo
        echo "Current reference \"$2\" does not match any matching parameter"
        echo "Current matching pattern: $1"
        exit 0
    fi
}

SetupEnvVars() {
    echo "BASH_ENV file: $BASH_ENV"
    if [ -f "$BASH_ENV" ]; then
        echo "Exists. Sourcing into ENV"
        # shellcheck disable=SC1090
        . "$BASH_ENV"
    else
        echo "Does Not Exist. Skipping file execution"
    fi
}

CheckEnvVars() {
    if [ -n "${MSTEAMS_DEFAULT_CHANNEL:-}" ]; then
        echo "It appears you have defined the MSTEAMS_DEFAULT_CHANNEL environment variable."
        echo "Please note, this will not have an effect.  MS Teams is setup such that a given webhook URL can only post to one channel."
    fi
    if [ -n "${MSTEAMS_PARAM_OFFSET:-}" ]; then
        echo "It appears you have defined the MSTEAMS_PARAM_OFFSET environment variable."
        echo "This feature is not supported and will not work."
    fi
    if [[ "$MSTEAMS_WEBHOOK" == "" ]]; then
        echo "In order to use the MS Teams Orb, a webhook URL must be present via the MSTEAMS_WEBHOOK environment variable."
        echo "Follow the setup guide: https://support.microsoft.com/en-us/office/create-incoming-webhooks-with-workflows-for-microsoft-teams-8ae491c7-0394-4861-ba59-055e33f75498"
        exit 1
    fi
    if [ -n "${MSTEAMS_PARAM_CHANNEL:-}" ]; then
        echo "It appears you have defined the MSTEAMS_PARAM_OFFSET environment variable."
        echo "Please note, this will not have an effect.  MS Teams is setup such that a given webhook URL can only post to one channel."
    fi
}

ShouldPost() {
    if [ "$CCI_STATUS" = "$MSTEAMS_PARAM_EVENT" ] || [ "$MSTEAMS_PARAM_EVENT" = "always" ]; then
        # In the event the MS Teams notification would be sent, first ensure it is allowed to trigger
        # on this branch or this tag.
        FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "${CIRCLE_BRANCH:-}"
        FilterBy "$MSTEAMS_PARAM_TAGPATTERN" "${CIRCLE_TAG:-}"

        echo "Posting Status"
    else
        # dont send message.
        echo "NO MS TEAMS ALERT"
        echo
        echo "This command is set to send an alert on: $MSTEAMS_PARAM_EVENT"
        echo "Current status: ${CCI_STATUS}"
        exit 0
    fi
}

SetupLogs() {
    if [ "$MSTEAMS_PARAM_DEBUG" -eq 1 ]; then
        LOG_PATH="$(mktemp -d 'msteams-orb-logs.XXXXXX')"
        MSTEAMS_MSG_BODY_LOG="$LOG_PATH/payload.json"
        MSTEAMS_SENT_RESPONSE_LOG="$LOG_PATH/response.json"

        touch "$MSTEAMS_MSG_BODY_LOG" "$MSTEAMS_SENT_RESPONSE_LOG"
        chmod 0600 "$MSTEAMS_MSG_BODY_LOG" "$MSTEAMS_SENT_RESPONSE_LOG"
    fi
}

# $1: Template with environment variables to be sanitized.
SanitizeVars() {
    [ -z "$1" ] && {
        printf '%s\n' "Missing argument."
        return 1
    }
    local template="$1"

    # Find all environment variables in the template with the format $VAR or ${VAR}.
    # The "|| true" is to prevent bats from failing when no matches are found.
    local variables
    variables="$(printf '%s\n' "$template" | grep -o -E '\$\{?[a-zA-Z_0-9]*\}?' || true)"
    [ -z "$variables" ] && {
        printf '%s\n' "Nothing to sanitize."
        return 0
    }

    # Extract the variable names from the matches.
    local variable_names
    variable_names="$(printf '%s\n' "$variables" | grep -o -E '[a-zA-Z0-9_]+' || true)"
    [ -z "$variable_names" ] && {
        printf '%s\n' "Nothing to sanitize."
        return 0
    }

    # Find out what OS we're running on.
    detect_os

    for var in $variable_names; do
        # The variable must be wrapped in double quotes before the evaluation.
        # Otherwise the newlines will be removed.
        local value
        value="$(eval printf '%s' \"\$"$var\"")"
        [ -z "$value" ] && {
            printf '%s\n' "$var is empty or doesn't exist. Skipping it..."
            continue
        }

        printf '%s\n' "Sanitizing $var..."

        local sanitized_value="$value"
        # Escape backslashes.
        sanitized_value="$(printf '%s' "$sanitized_value" | awk '{gsub(/\\/, "&\\"); print $0}')"
        # Escape newlines.
        sanitized_value="$(printf '%s' "$sanitized_value" | tr -d '\r' | awk 'NR > 1 { printf("\\n") } { printf("%s", $0) }')"
        # Escape double quotes.
        if [ "$PLATFORM" = "windows" ]; then
            sanitized_value="$(printf '%s' "$sanitized_value" | awk '{gsub(/"/, "\\\""); print $0}')"
        else
            sanitized_value="$(printf '%s' "$sanitized_value" | awk '{gsub(/\"/, "\\\""); print $0}')"
        fi

        # Write the sanitized value back to the original variable.
        # shellcheck disable=SC3045 # This is working on Alpine.
        printf -v "$var" "%s" "$sanitized_value"
    done

    return 0
}

# Will not run if sourced from another script.
# This is done so this script may be tested.
ORB_TEST_ENV="bats-core"
if [ "${0#*"$ORB_TEST_ENV"}" = "$0" ]; then
    # shellcheck source=/dev/null
    . "/tmp/MSTEAMS_JOB_STATUS"
    ShouldPost
    SetupEnvVars
    SetupLogs
    CheckEnvVars
    InstallJq
    BuildMessageBody
    PostToMsTeams
fi
set +x
