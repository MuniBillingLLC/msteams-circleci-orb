# MS Teams - CircleCI Orb Source

This Orb is a client for Microsoft Teams.  It was created by an org that
migrated from Slack to Teams and wanted to keep functionality in the Slack Orb
that was missing from the existing options for MS Teams such as:
  * Ability to `@` or mention a user
  * Ability to override the default template with a custom template
  * Ability to keep the on-hold functionality


You must define a `MSTEAMS_WEBHOOK` variable to use this Orb.  You need to
follow this How To in order to setup an integration in MS Teams that will let
you post a message to a Teams channel from a Webhook:
https://support.microsoft.com/en-us/office/create-incoming-webhooks-with-workflows-for-microsoft-teams-8ae491c7-0394-4861-ba59-055e33f75498


In order to use this Orb, you basically use it like the Slack orb, but rename
everything that begins with `SLACK_` to begin with `MSTEAMS_`.  Also, the
`on-hold` job has been renamed to `on_hold` b/c CircleCI doesn't allow dashes
in the name of a job for an Orb.


There is some functionality that was *NOT IMPLEMENTED* from the Slack Orb:
  * Thread functionality (the ability to send follow up messages as threaded
    responses).  This seemed really complicated and threads aren't that great
    in Teams so no attempt was made.
  * The ability to target a specific channel (or numerous channels).
    * This Orb relies on a Webhook URL which is tied to single MS Teams
      channel
  * The ability to schedule a message for delivery at a later time


Additionally, this integration uses the "Adaptive Card" format / spec defined
here: https://adaptivecards.io/explorer/


The Slack Orb sourcecode was used to help build this Orb:
https://github.com/CircleCI-Public/slack-orb
