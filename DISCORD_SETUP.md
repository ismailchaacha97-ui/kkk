# Roblox Hangout — Discord Server Setup Bot

This one-shot bot configures a **blank Discord server named Roblox Hangout** with roles, channels, permissions, pinned rules, and safety guides.

## What it creates

- **Roles:** Admin, Moderator, Event Host, Member, Muted, Bots
- **Information:** rules, welcome, announcements, role guide
- **Community:** general, media, creations, memes
- **Roblox:** looking-for-group, game-nights, trading safety, development
- **Events and voice:** event posts, Hangout voice, 10-person Gaming voice
- **Private staff area:** staff chat, manual moderation notes, admin-only chat

Public channels disallow `@everyone`/`@here` mentions and public/private thread creation by regular members. Staff channels are private. The Muted role blocks text participation and voice speaking/streaming. The bot never changes the global `@everyone` role.

## Safety properties

- **Dry run by default:** no changes unless you explicitly pass `--apply`.
- **Idempotent:** existing roles/channels and posted setup guides are reused, so rerunning does not create duplicates.
- **Non-destructive:** it deletes nothing and does not reconfigure existing roles/channels.
- **No privileged intents:** no Message Content or Server Members intent is required.
- **No credential storage:** the token is read locally from `.env`, which is ignored by Git.

> Use a newly created blank server. If a role or channel already exists, the bot reuses it without fixing its permissions; inspect any pre-existing objects yourself.

## 1. Create the blank server

1. In Discord, select **Add a Server** (`+`).
2. Select **Create My Own**, then **For a Club or Community**.
3. Name it **Roblox Hangout** and create it.

The server owner's own Discord account is not shared with the bot.

## 2. Create and invite the setup bot

1. Open the [Discord Developer Portal](https://discord.com/developers/applications) and choose **New Application**. Name it `Roblox Hangout Setup`.
2. Open **Bot**, select **Reset Token**, and copy the token locally. Treat it like a password: do not send it to anyone or paste it into chat.
3. Open **OAuth2 → URL Generator**:
   - Under **Scopes**, select **bot**.
   - Under **Bot Permissions**, select **Administrator**, **Manage Channels**, **Manage Roles**, **View Channels**, **Send Messages**, **Read Message History**, and **Manage Messages**. Administrator is required temporarily because Discord does not let a bot create Admin/Moderator roles with permissions the bot does not have itself. Manage Messages is used to pin the guides. Remove the setup bot after verifying the completed server so it does not retain unnecessary access.
4. Open the generated URL, select **Roblox Hangout**, and authorize it. You need permission to manage that server.
5. No settings under **Privileged Gateway Intents** need to be enabled.

## 3. Configure the local files

Install Python 3.10 or newer, then run from this project directory:

```bash
python -m venv .venv
source .venv/bin/activate        # Windows PowerShell: .venv\Scripts\Activate.ps1
python -m pip install -r requirements-discord.txt
cp .env.example .env             # Windows PowerShell: Copy-Item .env.example .env
```

In Discord, enable **User Settings → Advanced → Developer Mode**. Right-click the Roblox Hangout server icon and choose **Copy Server ID**.

Edit `.env`:

```dotenv
DISCORD_BOT_TOKEN=your_actual_bot_token
DISCORD_GUILD_ID=your_copied_numeric_server_id
```

Keep the quotes off both values. Do not use your Discord email, password, user token, or an invite code.

## 4. Preview and apply

Preview the entire layout with no credentials or connection:

```bash
python roblox_hangout_bot.py --print-plan
```

Run a read-only dry run against the server:

```bash
python roblox_hangout_bot.py
```

After reviewing the output, apply it:

```bash
python roblox_hangout_bot.py --apply
```

The bot connects, configures the server, prints its actions, and exits. If Discord interrupts the operation, fix the reported issue and run `--apply` again; completed objects will be reused.

## 5. Finish in Discord (manual safety review)

The bot does not change server-wide safety settings. Administrator is needed only during setup to create the elevated role presets; remove the setup bot after verification. After setup:

1. Assign **Admin** only to the owner and fully trusted managers. Assign **Moderator** to trained staff. Keep the setup bot's permissions unchanged until setup finishes.
2. Review **Server Settings → Roles** and every private channel. Confirm a test account cannot see **🛡️ STAFF** or post in information channels.
3. Open **Server Settings → Safety Setup**. Set a suitable verification level, enable the explicit media content filter, and configure Discord AutoMod for spam, suspected malicious links, and custom blocked words appropriate to your community.
4. Set **Default Notification Settings** to **Only @mentions**.
5. Optionally set **#👋│welcome** as the system messages channel for join notifications.
6. Recruit enough moderators for active time zones. Do not rely on the posted rules or this setup bot as automatic moderation.
7. Remove the setup bot from the server after verifying the result if it is no longer needed. It does not need to remain online for the roles, channels, or pinned messages to work.

## Important limits

This bot creates the server **structure**, not a complete moderation service. It does not provide automatic member verification, reaction roles, anti-raid protection, automatic moderation logs, ticket support, or Roblox account integration. The `mod-log` channel is explicitly labeled for manual notes. Do not advertise those features until you add and test them separately.

If a token is ever exposed, immediately use **Reset Token** in the Developer Portal. Never commit `.env`.
