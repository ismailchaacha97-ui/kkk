import unittest

import discord

import roblox_hangout_bot as setup


class ServerPlanTests(unittest.TestCase):
    def test_role_names_are_unique(self):
        names = [role.name.casefold() for role in setup.ROLE_SPECS]
        self.assertEqual(len(names), len(set(names)))
        self.assertEqual({role.key for role in setup.ROLE_SPECS}, {
            "admin", "moderator", "event_host", "member", "muted", "bots"
        })

    def test_channel_paths_are_unique(self):
        paths = [
            (category.name.casefold(), channel.name.casefold())
            for category in setup.CATEGORY_SPECS
            for channel in category.channels
        ]
        self.assertEqual(len(paths), len(set(paths)))
        self.assertEqual(len(paths), 18)

    def test_every_message_key_has_content_and_marker(self):
        used_keys = {
            channel.message_key
            for category in setup.CATEGORY_SPECS
            for channel in category.channels
            if channel.message_key
        }
        self.assertEqual(used_keys, set(setup.MESSAGES))
        for content in setup.MESSAGES.values():
            self.assertIn(setup.MESSAGE_MARKER, content)

    def test_only_admin_role_gets_administrator(self):
        for role in setup.ROLE_SPECS:
            permissions = setup.role_permissions(role.permissions)
            self.assertEqual(
                permissions.administrator,
                role.key == "admin",
                msg=role.name,
            )

    def test_public_text_disallows_mass_mentions_and_threads(self):
        for read_only in (False, True):
            overwrite = setup.public_text_overwrite(read_only=read_only)
            self.assertFalse(overwrite.mention_everyone)
            self.assertFalse(overwrite.create_public_threads)
            self.assertFalse(overwrite.create_private_threads)
            self.assertFalse(overwrite.send_messages_in_threads)
            self.assertEqual(overwrite.send_messages, not read_only)

    def test_muted_role_cannot_participate_in_text(self):
        overwrite = setup.muted_text_overwrite()
        self.assertFalse(overwrite.send_messages)
        self.assertFalse(overwrite.add_reactions)
        self.assertFalse(overwrite.send_messages_in_threads)

    def test_regular_roles_have_no_dangerous_guild_permissions(self):
        for role in setup.ROLE_SPECS:
            if role.key == "admin":
                continue
            permissions = setup.role_permissions(role.permissions)
            self.assertFalse(permissions.administrator)
            self.assertFalse(permissions.manage_guild)
            self.assertFalse(permissions.manage_roles)
            self.assertFalse(permissions.manage_channels)
            self.assertFalse(permissions.mention_everyone)

    def test_moderator_has_expected_moderation_permissions(self):
        permissions = setup.role_permissions("moderator")
        self.assertTrue(permissions.kick_members)
        self.assertTrue(permissions.ban_members)
        self.assertTrue(permissions.moderate_members)
        self.assertTrue(permissions.manage_messages)

    def test_permissions_object_is_discord_compatible(self):
        self.assertIsInstance(setup.role_permissions("event_host"), discord.Permissions)
        self.assertTrue(setup.role_permissions("event_host").manage_events)


if __name__ == "__main__":
    unittest.main()
