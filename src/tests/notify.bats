#!/usr/bin/env bats

setup() {
    source ./src/scripts/notify.sh
    source ./src/scripts/utils.sh
    export MSTEAMS_PARAM_BRANCHPATTERN=$(cat $BATS_TEST_DIRNAME/sampleBranchFilters.txt)
    MSTEAMS_PARAM_INVERT_MATCH="0"
}

@test "1: Skip message on no event" {
    CCI_STATUS="success"
    MSTEAMS_PARAM_EVENT="fail"
    echo "Running notify"
    run ShouldPost
    echo "test output status: $status"
    echo "Output:"
    echo "$output"
    echo " --- "
    [ "$status" -eq 0 ] # Check for no exit error
    [[ $output == *"NO MS TEAMS ALERT"* ]] # Ensure output contains expected string
}

@test "2: Mentions" {
    # Ensure mentions look OK
    MSTEAMS_PARAM_DEBUG=1
    MSTEAMS_PARAM_MENTIONS="user@example.com"
    MSTEAMS_PARAM_CUSTOM=$(cat $BATS_TEST_DIRNAME/sampleCustomTemplateWithMention.json)
    BuildMessageBody
    EXPECTED=$(echo "{\"type\":\"message\",\"attachments\":[{\"contentType\":\"application/vnd.microsoft.card.adaptive\",\"content\":{\"type\":\"AdaptiveCard\",\"body\":[{\"type\":\"Container\",\"style\":\"default\",\"items\":[{\"type\":\"FactSet\",\"facts\":[{\"title\":\"Mentions:\",\"value\":\"<at>user@example.com</at>\"}]}]}],\"actions\":[],\"msteams\":{\"entities\":[{\"type\":\"text\",\"text\":\"<at>user@example.com</at>\",\"mentioned\":{\"id\":\"user@example.com\",\"name\":\"user@example.com\"}}]}}}]}" | jq)
    [ "$MSTEAMS_MSG_BODY" == "$EXPECTED" ]
}

@test "3: empty test" {
    # test #3 is not applicable for MS Teams
    [ '""' == '""' ]
}

@test "4: ModifyCustomTemplate with environment variable in link" {
    TESTLINKURL="http://circleci.com"
    MSTEAMS_PARAM_CUSTOM=$(cat $BATS_TEST_DIRNAME/sampleCustomTemplateWithLink.json)
    BuildMessageBody
    EXPECTED=$(echo "{\"type\":\"message\",\"attachments\":[{\"contentType\":\"application/vnd.microsoft.card.adaptive\",\"content\":{\"type\":\"AdaptiveCard\",\"body\":[{\"type\":\"Container\",\"style\":\"default\",\"items\":[{\"type\":\"TextBlock\",\"text\":\"Sample link using environment variable http://circleci.com\"}]}],\"actions\":[],\"msteams\":{}}}]}" | jq)
    [ "$MSTEAMS_MSG_BODY" == "$EXPECTED" ]
}

@test "5: ModifyCustomTemplate special chars" {
    TESTLINKURL="http://circleci.com"
    MSTEAMS_PARAM_CUSTOM=$(cat $BATS_TEST_DIRNAME/sampleCustomTemplateWithSpecialChars.json)
    BuildMessageBody
    EXPECTED=$(echo "{\"type\":\"message\",\"attachments\":[{\"contentType\":\"application/vnd.microsoft.card.adaptive\",\"content\":{\"type\":\"AdaptiveCard\",\"body\":[{\"type\":\"Container\",\"style\":\"default\",\"items\":[{\"type\":\"TextBlock\",\"text\":\"These asterisks are not \`glob\`  patterns **t** (parentheses'). [Link](https://example.org)\"}]}],\"actions\":[],\"msteams\":{}}}]}" | jq)
    [ "$MSTEAMS_MSG_BODY" == "$EXPECTED" ]
}

@test "6: FilterBy - match-all default" {
    MSTEAMS_PARAM_BRANCHPATTERN=".+"
    CIRCLE_BRANCH="xyz-123"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error MSTEAMS_PARAM_BRANCHPATTERN debug: $MSTEAMS_PARAM_BRANCHPATTERN"
    echo "Error output debug: $output"
    [ "$output" == "" ] # Should match any branch: No output error
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "7: FilterBy - string" {
    CIRCLE_BRANCH="main"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [ "$output" == "" ] # "main" is in the list: No output error
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "8: FilterBy - regex numbers" {
    CIRCLE_BRANCH="pr-123"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [ "$output" == "" ] # "pr-[0-9]+" should match: No output error
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "9: FilterBy - non-match" {
    CIRCLE_BRANCH="x"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [[ "$output" =~ "NO MS TEAMS ALERT" ]] # "x" is not included in the filter. Error message expected.
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "10: FilterBy - no partial-match" {
    CIRCLE_BRANCH="pr-"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [[ "$output" =~ "NO MS TEAMS ALERT" ]] # Filter dictates that numbers should be included. Error message expected.
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "11: FilterBy - MSTEAMS_PARAM_BRANCHPATTERN is empty" {
    unset MSTEAMS_PARAM_BRANCHPATTERN
    CIRCLE_BRANCH="master"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "12: FilterBy - CIRCLE_BRANCH is empty" {
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "13: FilterBy - match and MSTEAMS_PARAM_INVERT_MATCH is set" {
    CIRCLE_BRANCH="pr-123"
    MSTEAMS_PARAM_INVERT_MATCH="1"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [[ "$output" =~ "NO MS TEAMS ALERT" ]] # "pr-[0-9]+" should match but inverted: Error message expected.
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "14: FilterBy - non-match and MSTEAMS_PARAM_INVERT_MATCH is set" {
    CIRCLE_BRANCH="foo"
    MSTEAMS_PARAM_INVERT_MATCH="1"
    run FilterBy "$MSTEAMS_PARAM_BRANCHPATTERN" "$CIRCLE_BRANCH"
    echo "Error output debug: $output"
    [ "$output" == "" ] # Nothing should match but inverted: No output error
    [ "$status" -eq 0 ] # In any case, this should return a 0 exit as to not block a build/deployment.
}

@test "15: Sanitize - Escape newlines in environment variables" {
    CIRCLE_JOB="$(printf "%s\\n" "Line 1." "Line 2." "Line 3.")"
    EXPECTED="Line 1.\\nLine 2.\\nLine 3."
    MSTEAMS_PARAM_CUSTOM=$(cat $BATS_TEST_DIRNAME/sampleCustomTemplate.json)
    SanitizeVars "$MSTEAMS_PARAM_CUSTOM"
    printf '%s\n' "Expected: $EXPECTED" "Actual: $CIRCLE_JOB"
    [ "$CIRCLE_JOB" = "$EXPECTED" ] # Newlines should be literal and escaped
}

@test "16: Sanitize - Escape double quotes in environment variables" {
    CIRCLE_JOB="$(printf "%s\n" "Hello \"world\".")"
    EXPECTED="Hello \\\"world\\\"."
    MSTEAMS_PARAM_CUSTOM=$(cat $BATS_TEST_DIRNAME/sampleCustomTemplate.json)
    SanitizeVars "$MSTEAMS_PARAM_CUSTOM"
    printf '%s\n' "Expected: $EXPECTED" "Actual: $CIRCLE_JOB"
    [ "$CIRCLE_JOB" = "$EXPECTED" ] # Double quotes should be escaped
}

@test "17: Sanitize - Escape backslashes in environment variables" {
    CIRCLE_JOB="$(printf "%s\n" "removed extra '\' from  notification template")"
    EXPECTED="removed extra '\\\' from  notification template"
    MSTEAMS_PARAM_CUSTOM=$(cat $BATS_TEST_DIRNAME/sampleCustomTemplate.json)
    SanitizeVars "$MSTEAMS_PARAM_CUSTOM"
    printf '%s\n' "Expected: $EXPECTED" "Actual: $CIRCLE_JOB"
    [ "$CIRCLE_JOB" = "$EXPECTED" ] # Backslashes should be escaped
}

@test "18: Sanitize - Remove carriage returns in environment variables" {
    MESSAGE="$(cat $BATS_TEST_DIRNAME/sampleVariableWithCRLF.txt)"
    MSTEAMS_PARAM_CUSTOM='{"text": "${MESSAGE}"}'
    BuildMessageBody

    EXPECTED=$(echo "{ \"text\": \"Multiline Message 1\nMultiline Message 2\" }" | jq)
    printf '%s\n' "Expected: $EXPECTED" "Actual: $MSTEAMS_MSG_BODY"
    [ "$MSTEAMS_MSG_BODY" = "$EXPECTED" ] # CRLF should be escaped
}
