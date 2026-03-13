import {
  ChannelType,
  Client,
  Events,
  GatewayIntentBits,
  Options,
  Partials,
  PermissionFlagsBits,
  REST,
  Routes,
  SlashCommandBuilder,
} from "discord.js";

const requiredEnv = [
  "DISCORD_TOKEN",
  "DISCORD_APP_ID",
  "DISCORD_PUBLIC_GUILD_ID",
  "DISCORD_INTERNAL_GUILD_ID",
  "DISCORD_ACTIVITY_ROLE_ID",
  "DISCORD_REPORT_CHANNEL_ID",
];

for (const key of requiredEnv) {
  if (!process.env[key]) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
}

const config = {
  token: process.env.DISCORD_TOKEN,
  appId: process.env.DISCORD_APP_ID,
  publicGuildId: process.env.DISCORD_PUBLIC_GUILD_ID,
  internalGuildId: process.env.DISCORD_INTERNAL_GUILD_ID,
  activityRoleId: process.env.DISCORD_ACTIVITY_ROLE_ID,
  reportChannelId: process.env.DISCORD_REPORT_CHANNEL_ID,
  commandRoleId: process.env.DISCORD_COMMAND_ROLE_ID || null,
  commandName: process.env.DISCORD_CHECK_COMMAND_NAME || "checkactivity",
  diagnoseCommandName: process.env.DISCORD_DIAGNOSE_COMMAND_NAME || "activitystatus",
  cacheTtlMs: Number.parseInt(process.env.DISCORD_CACHE_TTL_MS || "60000", 10),
  autoRegisterCommands: process.env.DISCORD_AUTO_REGISTER_COMMANDS !== "false",
};

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMembers,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.GuildMessageReactions,
    GatewayIntentBits.GuildVoiceStates,
  ],
  partials: [Partials.Message, Partials.Channel, Partials.Reaction],
  makeCache: Options.cacheWithLimits({
    MessageManager: 0,
    ReactionManager: 0,
    ReactionUserManager: 0,
    PresenceManager: 0,
    StageInstanceManager: 0,
    ThreadManager: 0,
    ThreadMemberManager: 0,
    GuildForumThreadManager: 0,
  }),
  sweepers: {
    ...Options.DefaultSweeperSettings,
    messages: {
      interval: 300,
      lifetime: 60,
    },
    reactions: {
      interval: 300,
      lifetime: 60,
    },
    users: {
      interval: 900,
      filter: () => (user) => !user.bot,
    },
  },
});

const removalCache = new Map();

function cleanupRemovalCache() {
  const now = Date.now();
  for (const [userId, expiresAt] of removalCache.entries()) {
    if (expiresAt <= now) {
      removalCache.delete(userId);
    }
  }
}

function markRemovalCache(userId) {
  removalCache.set(userId, Date.now() + config.cacheTtlMs);
}

function canSkipRemoval(userId) {
  cleanupRemovalCache();
  return (removalCache.get(userId) || 0) > Date.now();
}

function isTrackedGuild(guildId) {
  return guildId === config.publicGuildId || guildId === config.internalGuildId;
}

async function fetchTrackedGuilds() {
  const [publicGuild, internalGuild] = await Promise.all([
    client.guilds.fetch(config.publicGuildId),
    client.guilds.fetch(config.internalGuildId),
  ]);

  const [publicFull, internalFull] = await Promise.all([
    publicGuild.fetch(),
    internalGuild.fetch(),
  ]);

  return { publicGuild: publicFull, internalGuild: internalFull };
}

async function fetchAllMembers(guild) {
  await guild.members.fetch();
  return guild.members.cache;
}

async function removeActivityRole(userId, reason) {
  if (canSkipRemoval(userId)) {
    return { removed: false, reason: "cooldown" };
  }

  try {
    const internalGuild = await client.guilds.fetch(config.internalGuildId);
    const guild = await internalGuild.fetch();
    const member = await guild.members.fetch(userId).catch(() => null);

    if (!member) {
      console.warn(`Role removal skipped: user ${userId} is not a member of the internal guild`);
      return { removed: false, reason: "missing-member" };
    }

    if (!member.roles.cache.has(config.activityRoleId)) {
      return { removed: false, reason: "role-not-present" };
    }

    await member.roles.remove(config.activityRoleId, reason);
    markRemovalCache(userId);
    console.log(`Removed activity role from ${userId}: ${reason}`);
    return { removed: true, reason: "removed" };
  } catch (error) {
    console.error(`Failed to remove activity role from ${userId}: ${reason}`, error);
    return { removed: false, reason: "error", error };
  }
}

async function postRoleSnapshot(roleMembers) {
  const channel = await client.channels.fetch(config.reportChannelId);

  if (!channel?.isTextBased()) {
    throw new Error("Configured report channel is not a text channel");
  }

  const lines =
    roleMembers.length > 0
      ? roleMembers.map((member) => `- ${member.user.tag} (${member.id})`)
      : ["- nobody currently has the role"];

  await channel.send({
    content: [
      `Activity role snapshot for <@&${config.activityRoleId}>`,
      ...lines,
    ].join("\n"),
  });
}

async function runCheckActivity() {
  const { publicGuild, internalGuild } = await fetchTrackedGuilds();
  const [publicMembers, internalMembers] = await Promise.all([
    fetchAllMembers(publicGuild),
    fetchAllMembers(internalGuild),
  ]);

  const currentRoleMembers = internalMembers.filter((member) =>
    member.roles.cache.has(config.activityRoleId)
  );

  await postRoleSnapshot([...currentRoleMembers.values()]);

  const overlappingMembers = internalMembers.filter((member) => publicMembers.has(member.id));
  const membersToAssign = overlappingMembers.filter(
    (member) => !member.user.bot && !member.roles.cache.has(config.activityRoleId)
  );

  for (const member of membersToAssign.values()) {
    await member.roles.add(config.activityRoleId, "checkActivity overlap sync");
  }

  return {
    currentRoleCount: currentRoleMembers.size,
    overlapCount: overlappingMembers.size,
    assignedCount: membersToAssign.size,
  };
}

async function registerCommand() {
  const commands = [
    new SlashCommandBuilder()
      .setName(config.commandName)
      .setDescription("Snapshots the tracked role and assigns it to members on both servers")
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageRoles),
    new SlashCommandBuilder()
      .setName(config.diagnoseCommandName)
      .setDescription("Checks whether the bot can reach both servers, role, and report channel")
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageRoles),
  ];

  const rest = new REST({ version: "10" }).setToken(config.token);
  const commandPayloads = commands.map((command) => command.toJSON());
  const route = Routes.applicationGuildCommands(config.appId, config.internalGuildId);
  const existingCommands = await rest.get(route);

  const existingByName = new Map(
    Array.isArray(existingCommands) ? existingCommands.map((item) => [item.name, item]) : []
  );

  const unchanged =
    commandPayloads.length === existingByName.size &&
    commandPayloads.every((payload) => {
      const existingCommand = existingByName.get(payload.name);
      if (!existingCommand) {
        return false;
      }

      const permissionsMatch =
        String(existingCommand.default_member_permissions || "") ===
        String(payload.default_member_permissions || "");
      const descriptionMatch = existingCommand.description === payload.description;
      return permissionsMatch && descriptionMatch;
    });

  if (unchanged) {
    return;
  }

  await rest.put(route, { body: commandPayloads });
}

async function runDiagnostics() {
  const { publicGuild, internalGuild } = await fetchTrackedGuilds();
  const [role, reportChannel, appMember] = await Promise.all([
    internalGuild.roles.fetch(config.activityRoleId).catch(() => null),
    client.channels.fetch(config.reportChannelId).catch(() => null),
    internalGuild.members.fetchMe().catch(() => null),
  ]);

  const reportChannelOk =
    !!reportChannel &&
    reportChannel.isTextBased() &&
    reportChannel.guildId === config.internalGuildId;

  const activityRolePosition = role?.position ?? null;
  const botHighestRolePosition = appMember?.roles.highest?.position ?? null;
  const canManageRole =
    activityRolePosition !== null &&
    botHighestRolePosition !== null &&
    botHighestRolePosition > activityRolePosition;

  return {
    publicGuildName: publicGuild.name,
    internalGuildName: internalGuild.name,
    roleFound: !!role,
    reportChannelFound: reportChannelOk,
    botMemberFound: !!appMember,
    canManageRole,
    botHighestRolePosition,
    activityRolePosition,
  };
}

function memberCanRunCommand(interaction) {
  if (!interaction.inCachedGuild()) {
    return false;
  }

  if (!config.commandRoleId) {
    return interaction.memberPermissions.has(PermissionFlagsBits.ManageRoles);
  }

  return interaction.member.roles.cache.has(config.commandRoleId);
}

client.once(Events.ClientReady, async (readyClient) => {
  if (config.autoRegisterCommands) {
    await registerCommand();
  }
  console.log(`Discord bot logged in as ${readyClient.user.tag}`);
});

client.on(Events.InteractionCreate, async (interaction) => {
  if (
    !interaction.isChatInputCommand() ||
    (interaction.commandName !== config.commandName &&
      interaction.commandName !== config.diagnoseCommandName)
  ) {
    return;
  }

  if (interaction.guildId !== config.internalGuildId) {
    await interaction.reply({
      content: "This command can only be used in the internal server.",
      ephemeral: true,
    });
    return;
  }

  if (!memberCanRunCommand(interaction)) {
    await interaction.reply({
      content: "You are not allowed to use this command.",
      ephemeral: true,
    });
    return;
  }

  await interaction.deferReply({ ephemeral: true });

  try {
    if (interaction.commandName === config.commandName) {
      const result = await runCheckActivity();
      await interaction.editReply(
        `checkActivity finished. Existing role members: ${result.currentRoleCount}. ` +
          `Members on both servers: ${result.overlapCount}. Newly assigned: ${result.assignedCount}.`
      );
      return;
    }

    const diagnostics = await runDiagnostics();
    await interaction.editReply(
      [
        `Public guild: ${diagnostics.publicGuildName}`,
        `Internal guild: ${diagnostics.internalGuildName}`,
        `Activity role found: ${diagnostics.roleFound ? "yes" : "no"}`,
        `Report channel valid: ${diagnostics.reportChannelFound ? "yes" : "no"}`,
        `Bot member in internal guild: ${diagnostics.botMemberFound ? "yes" : "no"}`,
        `Role hierarchy OK: ${diagnostics.canManageRole ? "yes" : "no"}`,
        `Bot highest role position: ${diagnostics.botHighestRolePosition ?? "unknown"}`,
        `Activity role position: ${diagnostics.activityRolePosition ?? "unknown"}`,
      ].join("\n")
    );
  } catch (error) {
    console.error(`${interaction.commandName} failed`, error);
    await interaction.editReply(`${interaction.commandName} failed. Check container logs for details.`);
  }
});

client.on(Events.MessageCreate, async (message) => {
  if (!message.guildId || message.author.bot || !isTrackedGuild(message.guildId)) {
    return;
  }

  await removeActivityRole(message.author.id, `message activity in guild ${message.guildId}`);
});

client.on(Events.MessageReactionAdd, async (reaction, user) => {
  if (user.bot) {
    return;
  }

  let guildId = reaction.message.guildId;
  if (!guildId && reaction.partial) {
    await reaction.fetch().catch(() => null);
    guildId = reaction.message.guildId;
  }

  if (!guildId || !isTrackedGuild(guildId)) {
    return;
  }

  await removeActivityRole(user.id, `reaction activity in guild ${guildId}`);
});

client.on(Events.VoiceStateUpdate, async (oldState, newState) => {
  if (!newState.guild.id || !isTrackedGuild(newState.guild.id)) {
    return;
  }

  const joinedChannel = !oldState.channelId && !!newState.channelId;
  if (!joinedChannel) {
    return;
  }

  const channelType = newState.channel?.type;
  const isVoiceLike =
    channelType === ChannelType.GuildVoice || channelType === ChannelType.GuildStageVoice;

  if (!isVoiceLike) {
    return;
  }

  await removeActivityRole(newState.id, `voice activity in guild ${newState.guild.id}`);
});

client.login(config.token);
