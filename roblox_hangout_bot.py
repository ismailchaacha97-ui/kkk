#!/usr/bin/env python3
"""One-shot, idempotent setup bot for the Roblox Hangout Discord server.

Run without arguments for a read-only dry run. Pass --apply to make changes.
Requires DISCORD_BOT_TOKEN and DISCORD_GUILD_ID in the environment or a .env file.
"""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass, field
import os
import sys
from typing import Mapping

import discord
from dotenv import load_dotenv


SERVER_NAME = "Roblox Hangout"
SETUP_REASON = "Roblox Hangout initial server setup"
MESSAGE_MARKER = "<!-- roblox-hangout-setup:v1 -->"


@dataclass(frozen=True)
class RoleSpec:
    key: str
    name: str
    color: int
    permissions: str = "none"
    hoist: bool = False
    mentionable: bool = False


@dataclass(frozen=True)
class ChannelSpec:
    name: str
    kind: str = "text"
    policy: str = "discussion"
    topic: str = ""
    slowmode: int = 0
    user_limit: int = 0
    message_key: str | None = None


@dataclass(frozen=True)
class CategorySpec:
    name: str
    channels: tuple[ChannelSpec, ...]
    private_staff: bool = False


ROLE_SPECS = (
    RoleSpec("admin", "Admin", 0xE74C3C, "administrator", hoist=True),
    RoleSpec("moderator", "Moderator", 0x5865F2, "moderator", hoist=True),
    RoleSpec("event_host", "Event Host", 0xF1C40F, "event_host", hoist=True),
    RoleSpec("member", "Member", 0x57F287, hoist=True),
    RoleSpec("muted", "Muted", 0x747F8D),
    RoleSpec("bots", "Bots", 0x99AAB5, hoist=True),
)

CATEGORY_SPECS = (
    CategorySpec(
        "ℹ️ INFORMATION",
        (
            ChannelSpec(
                "📌│rules",
                policy="read_only",
                topic="Community rules and safety expectations. Read before participating.",
                message_key="rules",
            ),
            ChannelSpec(
                "👋│welcome",
                policy="read_only",
                topic="Start here to find your way around Roblox Hangout.",
                message_key="welcome",
            ),
            ChannelSpec(
                "📢│announcements",
                policy="read_only",
                topic="Official community announcements only.",
            ),
            ChannelSpec(
                "🎭│roles",
                policy="read_only",
                topic="Role guide. Staff will never ask for your password, token, or cookie.",
                message_key="roles",
            ),
        ),
    ),
    CategorySpec(
        "💬 COMMUNITY",
        (
            ChannelSpec(
                "💬│general",
                topic="Friendly Roblox conversation. Keep it safe and follow the rules.",
                slowmode=3,
            ),
            ChannelSpec(
                "📸│media",
                topic="Share appropriate Roblox screenshots and clips. No personal information.",
                slowmode=3,
            ),
            ChannelSpec(
                "🎨│creations",
                topic="Show your Roblox builds, avatars, art, and other creations.",
                slowmode=5,
            ),
            ChannelSpec(
                "😂│memes",
                topic="Lighthearted, appropriate Roblox memes only.",
                slowmode=5,
            ),
        ),
    ),
    CategorySpec(
        "🎮 ROBLOX",
        (
            ChannelSpec(
                "🔎│looking-for-group",
                topic="Find Roblox players. Share the game and your goal; never share private login details.",
                slowmode=5,
            ),
            ChannelSpec(
                "🎉│game-nights",
                topic="Coordinate community game nights and casual play sessions.",
                slowmode=3,
            ),
            ChannelSpec(
                "🔄│trading",
                topic="Roblox-item discussion only. No real-money deals, account sales, cross-trades, or trust trades.",
                slowmode=10,
                message_key="trading",
            ),
            ChannelSpec(
                "🛠️│development",
                topic="Discuss Roblox Studio, building, scripting, and game design.",
                slowmode=3,
            ),
        ),
    ),
    CategorySpec(
        "📅 EVENTS & VOICE",
        (
            ChannelSpec(
                "📅│events",
                policy="events",
                topic="Event Hosts post community event details here.",
                message_key="events",
            ),
            ChannelSpec("🔊│Hangout", kind="voice", policy="voice"),
            ChannelSpec("🎮│Gaming", kind="voice", policy="voice", user_limit=10),
        ),
    ),
    CategorySpec(
        "🛡️ STAFF",
        (
            ChannelSpec(
                "💼│staff-chat",
                policy="staff",
                topic="Private coordination for Admins and Moderators.",
            ),
            ChannelSpec(
                "🧾│mod-log",
                policy="staff",
                topic="Private moderation notes. This setup bot does not create automatic moderation logs.",
                message_key="mod_log",
            ),
            ChannelSpec(
                "🔐│admin-only",
                policy="admin",
                topic="Private Admin discussion. Never post credentials or user private data.",
            ),
        ),
        private_staff=True,
    ),
)


MESSAGES: Mapping[str, str] = {
    "rules": f"""# Roblox Hangout — Community Rules
{MESSAGE_MARKER}
**1. Be respectful.** No harassment, hate speech, threats, bullying, or targeted drama.
**2. Keep it safe.** No NSFW, sexual content, gore, or harmful content. Do not share personal information—including addresses, school details, phone numbers, or private images—yours or anyone else's.
**3. Prevent scams.** No phishing, malicious links, fake giveaways, impersonation, or requests for passwords, backup codes, cookies, or Discord tokens.
**4. Trade safely.** Discuss trades only for items supported by Roblox's official systems. No real-money transactions, account selling/sharing, cross-trading between platforms/games, trust trades, or paid middlemen.
**5. No spam.** Avoid flooding, repeated advertisements, mass mentions, and unsolicited server DMs. Ask a Moderator before promoting a server or project.
**6. Use channels correctly.** Keep content on-topic and use appropriate channels for media, trading, and development.
**7. Follow platform rules.** Discord's Terms of Service and Community Guidelines and Roblox's Community Standards apply. You must meet Discord's minimum age requirement for your country.
**8. Work with staff.** Do not evade timeouts, mutes, or bans with alternate accounts. Contact an Admin privately and respectfully if you believe a moderation action was wrong.

**Stay safe:** Staff will never ask for your password, cookie, backup codes, or bot token. Use Roblox's official trade window and Discord's blocking/reporting tools when needed.""",
    "welcome": f"""# Welcome to Roblox Hangout! 👋
{MESSAGE_MARKER}
A friendly place to meet Roblox players, share creations, join game nights, and talk about development.

**Start here:**
1. Read **#📌│rules**.
2. Check **#📢│announcements** and **#📅│events**.
3. Introduce yourself in **#💬│general**—please do not share personal information.
4. Use **#🔎│looking-for-group** to find teammates and **#🎨│creations** to show your work.

Protect your account: never share your password, cookie, backup codes, or Discord token. Have fun!""",
    "roles": f"""# Role Guide
{MESSAGE_MARKER}
**Admin** — Trusted server managers with full permissions. Assign this role sparingly.
**Moderator** — Keeps the community safe and manages messages and moderation actions.
**Event Host** — Posts and organizes community events.
**Member** — Community identity role; it grants no special permissions.
**Muted** — Temporarily prevents participation in text and voice channels.
**Bots** — Identifies bot accounts; it grants no special permissions by itself.

Roles are assigned manually by server staff. This setup bot does not provide reaction roles or automatic role assignment.""",
    "trading": f"""# Trading Safety 📌
{MESSAGE_MARKER}
- Use Roblox's official trading systems; never trust a screenshot as proof of a completed trade.
- **No real-money transactions, account sales/sharing, cross-trades, trust trades, or paid middlemen.**
- Never share passwords, cookies, backup codes, or Discord tokens—even with someone claiming to be staff.
- Do not open suspicious links or download files to receive an item.
- Report suspected scams to Moderators with relevant evidence; avoid public harassment or witch hunts.""",
    "events": f"""# Community Events
{MESSAGE_MARKER}
Event Hosts should include the event name, Roblox experience, date, time **with timezone**, joining instructions, and any age-appropriate safety information.

Do not post private server links publicly if they expose personal information. Never charge real money for entry or require users to disable account safety features.""",
    "mod_log": f"""# Moderation Notes
{MESSAGE_MARKER}
Record actions consistently: user ID, reason, evidence, action, duration, and responsible staff member. Keep personal data to an absolute minimum.

This channel is for manual staff notes; the one-shot setup bot does not provide automatic moderation logging.""",
}


def role_permissions(kind: str) -> discord.Permissions:
    """Return least-privilege guild permissions for a configured role."""
    permissions = discord.Permissions.none()
    if kind == "none":
        return permissions
    if kind == "administrator":
        return discord.Permissions(administrator=True)
    if kind == "moderator":
        permissions.update(
            view_audit_log=True,
            kick_members=True,
            ban_members=True,
            moderate_members=True,
            manage_messages=True,
            manage_threads=True,
        )
        return permissions
    if kind == "event_host":
        permissions.update(manage_events=True)
        return permissions
    raise ValueError(f"Unknown role permission preset: {kind}")


def public_text_overwrite(read_only: bool = False) -> discord.PermissionOverwrite:
    return discord.PermissionOverwrite(
        view_channel=True,
        send_messages=not read_only,
        add_reactions=True,
        embed_links=not read_only,
        attach_files=not read_only,
        read_message_history=True,
        mention_everyone=False,
        create_public_threads=False,
        create_private_threads=False,
        send_messages_in_threads=False,
        use_application_commands=True,
    )


def muted_text_overwrite() -> discord.PermissionOverwrite:
    return discord.PermissionOverwrite(
        send_messages=False,
        add_reactions=False,
        create_public_threads=False,
        create_private_threads=False,
        send_messages_in_threads=False,
    )


def build_overwrites(
    guild: discord.Guild,
    roles: Mapping[str, discord.Role],
    policy: str,
) -> dict[discord.abc.Snowflake, discord.PermissionOverwrite]:
    """Build explicit channel overwrites; never alter @everyone globally."""
    everyone = guild.default_role
    bot_member = guild.me
    if bot_member is None:
        raise RuntimeError("The bot member is unavailable in this server.")

    bot_access = discord.PermissionOverwrite(
        view_channel=True,
        send_messages=True,
        read_message_history=True,
        manage_messages=True,
        connect=True,
    )
    overwrites: dict[discord.abc.Snowflake, discord.PermissionOverwrite] = {
        bot_member: bot_access
    }

    if policy == "voice":
        overwrites[everyone] = discord.PermissionOverwrite(
            view_channel=True,
            connect=True,
            speak=True,
            stream=True,
            send_messages=True,
            read_message_history=True,
            mention_everyone=False,
        )
        overwrites[roles["muted"]] = discord.PermissionOverwrite(
            send_messages=False,
            add_reactions=False,
            speak=False,
            stream=False,
        )
        return overwrites

    if policy in {"discussion", "read_only", "events"}:
        overwrites[everyone] = public_text_overwrite(read_only=policy != "discussion")
        overwrites[roles["muted"]] = muted_text_overwrite()
        overwrites[roles["moderator"]] = discord.PermissionOverwrite(
            view_channel=True,
            send_messages=True,
            manage_messages=True,
            read_message_history=True,
        )
        if policy == "events":
            overwrites[roles["event_host"]] = discord.PermissionOverwrite(
                view_channel=True,
                send_messages=True,
                read_message_history=True,
            )
        return overwrites

    if policy in {"staff", "admin"}:
        overwrites[everyone] = discord.PermissionOverwrite(view_channel=False)
        overwrites[roles["muted"]] = discord.PermissionOverwrite(view_channel=False)
        if policy == "staff":
            overwrites[roles["moderator"]] = discord.PermissionOverwrite(
                view_channel=True,
                send_messages=True,
                manage_messages=True,
                read_message_history=True,
            )
        else:
            overwrites[roles["moderator"]] = discord.PermissionOverwrite(view_channel=False)
            overwrites[roles["admin"]] = discord.PermissionOverwrite(
                view_channel=True,
                send_messages=True,
                read_message_history=True,
            )
        return overwrites

    raise ValueError(f"Unknown channel policy: {policy}")


def find_role(guild: discord.Guild, name: str) -> discord.Role | None:
    return next((role for role in guild.roles if role.name.casefold() == name.casefold()), None)


def find_category(guild: discord.Guild, name: str) -> discord.CategoryChannel | None:
    return next(
        (
            channel
            for channel in guild.categories
            if channel.name.casefold() == name.casefold()
        ),
        None,
    )


def find_channel(
    category: discord.CategoryChannel,
    spec: ChannelSpec,
) -> discord.TextChannel | discord.VoiceChannel | None:
    candidates = category.text_channels if spec.kind == "text" else category.voice_channels
    return next(
        (channel for channel in candidates if channel.name.casefold() == spec.name.casefold()),
        None,
    )


def print_plan(guild: discord.Guild | None = None) -> None:
    print(f"\nPlanned setup for {SERVER_NAME}")
    print("Existing objects are reused and never deleted or reconfigured.\n")
    for spec in ROLE_SPECS:
        status = ""
        if guild is not None:
            status = " [exists]" if find_role(guild, spec.name) else " [create]"
        print(f"Role: {spec.name}{status}")
    for category_spec in CATEGORY_SPECS:
        category = find_category(guild, category_spec.name) if guild is not None else None
        status = ""
        if guild is not None:
            status = " [exists]" if category else " [create]"
        print(f"\nCategory: {category_spec.name}{status}")
        for channel_spec in category_spec.channels:
            channel_status = ""
            if guild is not None:
                exists = category is not None and find_channel(category, channel_spec)
                channel_status = " [exists]" if exists else " [create]"
            print(f"  {channel_spec.kind}: {channel_spec.name}{channel_status}")
    print()


async def ensure_roles(guild: discord.Guild) -> dict[str, discord.Role]:
    roles: dict[str, discord.Role] = {}
    for spec in ROLE_SPECS:
        existing = find_role(guild, spec.name)
        if existing:
            print(f"Reusing role: {spec.name}")
            roles[spec.key] = existing
            continue
        print(f"Creating role: {spec.name}")
        roles[spec.key] = await guild.create_role(
            name=spec.name,
            permissions=role_permissions(spec.permissions),
            colour=discord.Colour(spec.color),
            hoist=spec.hoist,
            mentionable=spec.mentionable,
            reason=SETUP_REASON,
        )
    return roles


async def ensure_channel_message(channel: discord.TextChannel, message_key: str) -> None:
    content = MESSAGES[message_key]
    async for message in channel.history(limit=50):
        if message.author == channel.guild.me and MESSAGE_MARKER in message.content:
            if not message.pinned:
                await message.pin(reason=SETUP_REASON)
                print(f"Re-pinned existing setup message: #{channel.name}")
            else:
                print(f"Setup message already present and pinned: #{channel.name}")
            return
    message = await channel.send(content)
    await message.pin(reason=SETUP_REASON)
    print(f"Posted and pinned setup message: #{channel.name} ({message_key})")


async def ensure_structure(guild: discord.Guild, roles: Mapping[str, discord.Role]) -> None:
    for category_spec in CATEGORY_SPECS:
        category = find_category(guild, category_spec.name)
        if category is None:
            print(f"Creating category: {category_spec.name}")
            category_overwrites = (
                build_overwrites(guild, roles, "staff")
                if category_spec.private_staff
                else None
            )
            category = await guild.create_category(
                category_spec.name,
                overwrites=category_overwrites,
                reason=SETUP_REASON,
            )
        else:
            print(f"Reusing category: {category_spec.name}")

        for spec in category_spec.channels:
            existing = find_channel(category, spec)
            if existing is not None:
                print(f"Reusing channel: {spec.name}")
                if spec.message_key and isinstance(existing, discord.TextChannel):
                    await ensure_channel_message(existing, spec.message_key)
                continue

            print(f"Creating {spec.kind} channel: {spec.name}")
            overwrites = build_overwrites(guild, roles, spec.policy)
            if spec.kind == "text":
                channel = await category.create_text_channel(
                    spec.name,
                    topic=spec.topic,
                    slowmode_delay=spec.slowmode,
                    overwrites=overwrites,
                    reason=SETUP_REASON,
                )
                if spec.message_key:
                    await ensure_channel_message(channel, spec.message_key)
            elif spec.kind == "voice":
                await category.create_voice_channel(
                    spec.name,
                    user_limit=spec.user_limit,
                    overwrites=overwrites,
                    reason=SETUP_REASON,
                )
            else:
                raise ValueError(f"Unknown channel kind: {spec.kind}")


def validate_guild_access(guild: discord.Guild) -> None:
    member = guild.me
    if member is None:
        raise RuntimeError("The bot is not a member of the selected server.")
    required = {
        "manage_channels": "Manage Channels",
        "manage_roles": "Manage Roles",
        "view_channel": "View Channels",
        "send_messages": "Send Messages",
        "read_message_history": "Read Message History",
        "manage_messages": "Manage Messages (to pin guides)",
    }
    missing = [label for attr, label in required.items() if not getattr(member.guild_permissions, attr)]
    if missing:
        raise RuntimeError("Missing bot permissions: " + ", ".join(missing))


async def run(token: str, guild_id: int, apply: bool) -> None:
    intents = discord.Intents.none()
    intents.guilds = True
    bot = discord.Client(intents=intents)
    setup_failed = False

    @bot.event
    async def on_ready() -> None:
        nonlocal setup_failed
        try:
            guild = bot.get_guild(guild_id)
            if guild is None:
                raise RuntimeError(
                    f"Guild {guild_id} was not found. Invite the bot to {SERVER_NAME} and verify DISCORD_GUILD_ID."
                )
            validate_guild_access(guild)
            print_plan(guild)
            if not apply:
                print("DRY RUN: no server objects or messages were changed. Use --apply after reviewing this plan.")
                return
            roles = await ensure_roles(guild)
            await ensure_structure(guild, roles)
            print("Setup complete. Re-running is safe: existing objects and posted guides are reused.")
        except Exception as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            setup_failed = True
        finally:
            await bot.close()

    await bot.start(token)
    if setup_failed:
        raise RuntimeError("Setup did not complete; review the error above.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Configure the Roblox Hangout Discord server safely and idempotently."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply changes. Without this flag, only a read-only dry run is performed.",
    )
    parser.add_argument(
        "--print-plan",
        action="store_true",
        help="Print the planned layout without connecting to Discord or requiring credentials.",
    )
    return parser.parse_args()


def main() -> int:
    load_dotenv()
    args = parse_args()
    if args.print_plan:
        print_plan()
        return 0

    token = os.getenv("DISCORD_BOT_TOKEN", "").strip()
    guild_id_text = os.getenv("DISCORD_GUILD_ID", "").strip()
    if not token or not guild_id_text:
        print(
            "ERROR: Set DISCORD_BOT_TOKEN and DISCORD_GUILD_ID in .env. See DISCORD_SETUP.md.",
            file=sys.stderr,
        )
        return 2
    try:
        guild_id = int(guild_id_text)
    except ValueError:
        print("ERROR: DISCORD_GUILD_ID must contain only the numeric server ID.", file=sys.stderr)
        return 2
    if guild_id <= 0:
        print("ERROR: DISCORD_GUILD_ID must be a positive numeric server ID.", file=sys.stderr)
        return 2

    try:
        asyncio.run(run(token, guild_id, args.apply))
    except (discord.LoginFailure, discord.PrivilegedIntentsRequired):
        print("ERROR: Discord rejected the bot login. Check the token; no privileged intents are needed.", file=sys.stderr)
        return 1
    except (discord.HTTPException, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
