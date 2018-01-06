-- ============================================================================
--
-- Player and Commander Levelling System (Controller)
--      Throughout the game, players and accumulate Experience points (XP)
--      when they perform various actions as spcified in the formula config
--      These XP then contributes to the requirements of reaching the next
--      level. Each level has a set required amount of points as specified
--      by the formula in the config and also a corresponding badge to
--      represent the level attained.
--
-- The controller handles all the Shine Hooks and passes data into the self.Levels
-- model for processing
--
-- ============================================================================

-- ============================================================================
-- ----------------------------------------------------------------------------
-- Initialisation
-- ----------------------------------------------------------------------------
-- ============================================================================

local Shine = Shine
local Levelling = {}

Levelling.Settings = {}

-- ============================================================================
-- Levelling:Initialise
-- Initialise the Leveling plguin by Shine
-- ============================================================================

function Levelling:Initialise(LevellingConfig, Notifications, Badges,
    Levels, Plugin)
    -- Load Config File
    self.Settings = LevellingConfig
    -- Checks if Config debug mode is enabled. Returns false if failed checking
    -- Debug mode can be turned off to improve performance
    if self.Settings.Enabled then
        if self.Settings.ConfigDebug and not self:CheckConfig(self.Settings) then
            self.Settings.Enabled = false
            return false
        else
            self.Notifications = Notifications
            self.Badges = Badges
            self.Levels = Levels
            self:CreateLevellingCommands(Plugin)
            return true
        end
    end
end

-- ============================================================================
-- Levelling:CheckConfig
-- Checks the config for correctness
-- ============================================================================

function Levelling:CheckConfig(LevellingConfig)
    local CheckFlag = true

    -- Checks if Player leveling configs are correct
    if LevellingConfig.Player.Enabled then
        if string.find(LevellingConfig.Player.NextLevelFormula.Formula, "x")
            == nil then
            error("ShineCredits Levelling:CheckConfig() - Error in config, " ..
                "Player.NextLevelFormula.Formula must contain " ..
                "a letter x to signify level as a variable")
            CheckFlag = false
        end

    -- Checks if Player badges configs are correct
    elseif LevellingConfig.Player.Badges.Enabled then
        if #LevellingConfig.Player.Badges.CustomBadgesOrder <
        LevellingConfig.Player.NextLevelFormula.MaximumLevel then
            error("ShineCredits Levelling:CheckConfig() - Error in config, " ..
            "Player.Badges.CustomBadgesOrder must have more" ..
            "elements (badges) than the number of self.Levels")
            CheckFlag = false
        elseif LevellingConfig.Player.Badges.BadgesOrder.BadgeRow
        < 1 then
            error("ShineCredits Levelling:CheckConfig() - Error in config, " ..
            "Commander.Badges.BadgesOrder.LocalBadgeRow must be " ..
            "greater than 0")
            CheckFlag = false
        end
    end

    -- Checks if Commander leveling configs are correct
    if LevellingConfig.Commander.Enabled then
        if string.find(LevellingConfig.Commander.NextLevelFormula.Formula, "x")
            == nil then
            error("ShineCredits Levelling:CheckConfig() - Error in config, " ..
                "Commander.NextLevelFormula.Formula must contain " ..
                "a letter x to signify level as a variable")
            CheckFlag = false
        end

    -- Checks if Commander badges configs are correct
    elseif LevellingConfig.Commander.Badges.Enabled then
        if #LevellingConfig.Commander.Badges.CustomBadgesOrder <
        LevellingConfig.Commander.NextLevelFormula.MaximumLevel then
            error("ShineCredits Levelling:CheckConfig() - Error in config, " ..
            "Commander.Badges.CustomBadgesOrder must have more" ..
            "elements (badges) than the number of self.Levels")
            CheckFlag = false
        elseif LevellingConfig.Commander.Badges.BadgesOrder.BadgeRow
        < 1 then
            error("ShineCredits Levelling:CheckConfig() - Error in config, " ..
            "Commander.Badges.BadgesOrder.LocalBadgeRow must be " ..
            "greater than 0")
            CheckFlag = false
        end
    end
    return CheckFlag
end

-- ============================================================================
-- ----------------------------------------------------------------------------
-- Hooks
-- ----------------------------------------------------------------------------
-- ============================================================================

-- ============================================================================
-- Levelling:PostJoinTeam
-- Starts or stops XP accrueing upon joining or leaving a
-- playing team respectively
-- ============================================================================
function Levelling:PostJoinTeam( Gamerules, Player, OldTeam, NewTeam, Force, ShineForce )
    local AwardSettings = self.Settings.AwardedWhen
    if Gamerules:GetGameStarted() then
        -- Check if team changed to is 0: Ready room , 3:Spectators
        if (NewTeam == 0 or NewTeam == 3) and AwardSettings.LeaveTeam then
            self:StopXP(Player)
        else
            self:StartXP(Player)
        end
        return true
    end
    return false
end

-- ============================================================================
-- Levelling:SetGameState
-- Starts or stops XP accrueing when game changes state
-- ============================================================================
function Levelling:SetGameState( Gamerules, NewState, OldState )
    -- If new state is 5:"Game Started"
    if NewState == 5 then
        self:StartXPAllInTeam()
    elseif NewState >= 6 and NewState < 9 then
        self:StopXPAllInTeam(NewState)
    end
    return true
end

-- ============================================================================
-- Levelling:ClientConnect
-- Introduce player into the system
-- ============================================================================
function Levelling:ClientConnect( Client )
    if self.Settings.Enabled then
        self.Levels:InitPlayer( Client:GetControllingPlayer() )
        return true
    else
        return false
    end
end

-- ============================================================================
-- ----------------------------------------------------------------------------
-- Core Functions
-- ----------------------------------------------------------------------------
-- ============================================================================
-- ============================================================================
-- Levelling:StartXP
-- Starts accruing XP for the player
-- ============================================================================
function Levelling:StartXP( Player )
    return true
end

-- ============================================================================
-- Levelling:StopXP
-- Stops accruing XP for the player, calculate and award XP
-- ============================================================================
function Levelling:StopXP( Player, Victory )
    local Settings = self.Settings
    local FormulaPlayer = Settings.Player.XPFormula
    local FormulaCommander = Settings.Commander.XPFormula

    local PlayerXPAwarded = 0
    local CommanderXPAwarded = 0

    -- Return false if player is not in a group allowed for leveling or
    --      in a group suspended from leveling
    if not self:GetAllowedForLeveling( Player ) then
        return false
    end

    -- Calculate Player XP
    PlayerXPAwarded =
    math.Round(FormulaPlayer.Formula.Time.XPPerMinute *
        math.Round(Player:GetPlayTime()/60,0),0) +
    math.Round(FormulaPlayer.Formula.Score.XPPerScore * Player:GetScore(),0) +
    math.Round(FormulaPlayer.Formula.Score.XPPerKill * Player:GetKills(),0) +
    math.Round(FormulaPlayer.Formula.Score.XPPerAssist * Player:GetAssistKills(),0)

    -- Calculate Commander XP
    CommanderXPAwarded =
    math.Round(FormulaCommander.Formula.Time.XPPerMinute *
        math.Round(Player:GetCommanderTime()/60,0),0)

    -- Apply Multipliers
    if Victory then
        PlayerXPAwarded = math.Round(PlayerXPAwarded
            * FormulaPlayer.Formula.Multipliers.Victory,0)
        CommanderXPAwarded = math.Round(CommanderXPAwarded
            * FormulaCommander.Formula.Multipliers.Victory,0)
    end

    -- Ensure that XP awarded does not go beyond maximum
    PlayerXPAwarded = Clamp(PlayerXPAwarded,0,
        FormulaPlayer.MaximumAwardedPerRound)
    CommanderXPAwarded = Clamp(CommanderXPAwarded,0,
        FormulaPlayer.MaximumAwardedPerRound)

    -- Add the XP awarded
    self.Levels:AddPlayerXP( Player, PlayerXPAwarded )
    self.Levels:AddCommanderXP( Player, CommanderXPAwarded)

    self:UpdateLevel( Player, self.Levels:GetPlayerXP( Player ), false)
    self:UpdateLevel( Player, self.Levels:GetCommanderXP( Player ), true)

    self.Levels:SaveLevels()

    return true

end

-- ============================================================================
-- Levelling:StartXPAllInTeam
-- Starts accruing XP for the player for all players in playing teams
-- ============================================================================
function Levelling:StartXPAllInTeam()
    local team1Players = GetGamerules():GetTeam1():GetPlayers()
    local team2Players = GetGamerules():GetTeam2():GetPlayers()

    -- For all players in Marines
    for _, team1Player in ipairs(team1Players) do
        self:StartXP(team1Player)
    end

    -- For all players in Aliens
    for _, team2Player in ipairs(team2Players) do
        self:StartXP(team2Player)
    end

end

-- ============================================================================
-- Levelling:StopXPAllInTeam
-- Stops accruing XP for the player for all players in playing teams
-- ============================================================================
function Levelling:StopXPAllInTeam(GameState)
    local team1Players = GetGamerules():GetTeam1():GetPlayers()
    local team2Players = GetGamerules():GetTeam2():GetPlayers()
    local MarineVictoryFlag = false
    local AlienVictoryFlag = false

    if GameState == 6 then
        MarineVictoryFlag = true
    elseif GameState == 7 then
        AlienVictoryFlag = true
    end

    for _, team1Player in ipairs(team1Players) do
        self:StopXP(team1Player, MarineVictoryFlag)
    end

    for _, team2Player in ipairs(team2Players) do
        self:StopXP(team2Player, AlienVictoryFlag)
    end
end

-- ============================================================================
-- Levelling:UpdatePlayerLevel
-- Updates the player's level
-- ============================================================================

function Levelling:UpdateLevel( Player, CurrentXP, Commander)
    -- Initialise local variables with global values
    local Settings = self.Settings

    -- Get the current level of the Player
    local PreviousLevel = 0
    local NotificationText = ""

    if Commander then
        Settings = Settings.Commander
        PreviousLevel = self.Levels:GetCommanderLevel( Player )
    else
        Settings = Settings.Player
        PreviousLevel = self.Levels:GetPlayerLevel( Player )
    end

    -- If player is already at max level
    if PreviousLevel == Settings.NextLevelFormula.MaximumLevel then
        return nil
    end

    -- Determine the player's new level
    local NewLevel = self:GetCorrectLevel(
        Settings.NextLevelFormula.Formula,
        CurrentXP,
        PreviousLevel,
        Settings.NextLevelFormula.MaximumLevel)

    -- If player's Level has changed, perform badge change
    if PreviousLevel ~= NewLevel then
        local CustomOrder = Settings.Badges.CustomBadgesOrder
        if CustomOrder and #CustomOrder > 0 then
            if CustomOrder[NewLevel] then
                self.Badges:SwitchBadge(Player ,
                CustomOrder[PreviousLevel],
                CustomOrder[NewLevel], Settings.Badges.BadgeRow)
            else
                error("ShineXP sc_playerleveling.lua: Custom Level " ..
                    "Badges has no badges specified for level " .. NewLevel ..
                    ", check your config file!")
                return false
            end
        else
            local NewBadge = Settings.Badges.BadgesOrder.LevelBadgeNamePrefix ..
                NewLevel ..
                Settings.Badges.BadgesOrder.LevelBadgeNameSuffix

            local OldBadge = Settings.Badges.BadgesOrder.LevelBadgeNamePrefix ..
                PreviousLevel ..
                Settings.Badges.BadgesOrder.LevelBadgeNameSuffix

            self.Badges:SwitchBadge(Player,OldBadge,
                NewBadge,Settings.Badges.BadgeRow)
        end

        -- Commit changes to files
        if Commander then
            self.Levels:SetCommanderLevel( Player, NewLevel)
            NotificationText = Settings.Notifications.LevelChange
        else
            self.Levels:SetPlayerLevel( Player, NewLevel)
            NotificationText = Settings.Notifications.LevelChange
        end

        self.Notifications:Notify(Player,
            string.format(NotificationText,NewLevel))

        Shine:SaveUsers( true )

        return NewLevel
    else
        return nil
    end
end


-- ============================================================================
-- ----------------------------------------------------------------------------
-- Helper Functions
-- ----------------------------------------------------------------------------
-- ============================================================================

-- ============================================================================
-- Levelling:GetAllowedForLeveling
-- Checks if the player belongs to a user group that has leveling suspended
-- ============================================================================
function Levelling:GetAllowedForLeveling( Player )
    -- Initialise local variables with global values
    local Settings = self.Settings

    -- Obtain required data on player to check player's group
    local Target = Player:GetClient()
    local Existing, _ = Shine:GetUserData( Target )

    -- Return false if player is in a group suspended from leveling
    if Settings.Permissions.SuspendLevelingForGroup then
        for _, group in ipairs(Settings.Permissions.SuspendLevelingForGroup) do
            if group == Existing.Group then
                return false
            end
        end
        return true
    else
        return true
    end
end

-- ============================================================================
-- Levelling:GetCorrectLevel:
-- Calculate the player's actual level, based on the formula specified
-- ============================================================================
function Levelling:GetCorrectLevel( CustomFormula, CurrentXP
    , CurrentLevel, MaxLevel )
    local FormulaFunction = nil

    CustomFormula = "return " .. CustomFormula
    FormulaFunction = loadstring(CustomFormula)

    -- Substitute x for the current level of the player/commander
    local LoopFormula = CustomFormula:gsub("x", CurrentLevel)
    FormulaFunction = loadstring(LoopFormula)

    -- Check if the formula is a valid mathematical construct
    if not FormulaFunction() then
        error("ShineCredits self.Levels:GetCorrectLevel - Formula provided is " ..
        "not valid.")
    end

    -- Checks which way to update the player's level
    if CurrentXP < FormulaFunction() then
        -- When player's total XP is less than Level's required XP:
        --      Decrease player's Level by 1 until player's XP is
        --      equivalent to the required amount
        while (CurrentXP < FormulaFunction())
        and CurrentLevel ~= MaxLevel do
            CurrentLevel = CurrentLevel - 1
            LoopFormula = CustomFormula:gsub("x", CurrentLevel)
            FormulaFunction = loadstring(LoopFormula)
        end
    else
        -- When player's total XP is more than Level's required XP:
        --      Increase player's Level by 1 until player's XP is
        --      equivalent to the required amount
        while (CurrentXP > FormulaFunction() )
        and CurrentLevel ~= MaxLevel do
            CurrentLevel = CurrentLevel + 1
            LoopFormula = CustomFormula:gsub("x", CurrentLevel)
            FormulaFunction = loadstring(LoopFormula)
        end
    end
    return CurrentLevel
end

-- ============================================================================
-- ----------------------------------------------------------------------------
-- Commands
-- ----------------------------------------------------------------------------
-- ============================================================================
function Levelling:CreateLevellingCommands(Plugin)
    local Settings = self.Settings
    local CommandsFile = self.Settings.Commands
    local Levels = self.Levels

    -- ====== Set XP ======
    local function SetXP( Client, Targets, AmountPlayer, AmountCommander)
        local LocalPlayer = Client:GetControllingPlayer()
        for i = 1, #Targets do
            SteamID = tostring(Targets[ i ]:GetUserId())
            Levels:SetPlayerXP( Client:GetControllingPlayer(),
                AmountPlayer )
            Levels:SetCommanderXP( Client:GetControllingPlayer(),
                AmountCommander )
        end
        Levels:SaveLevels()

        self.Notifications:Notify(LocalPlayer, "XP Set")
        self.Notifications:ConsoleMessage( LocalPlayer, "XP Set" )
    end
	local SetXPCommand = Plugin:BindCommand( CommandsFile.SetXP.Console,
        CommandsFile.SetXP.Chat, SetXP )
    SetXPCommand:AddParam{ Type = "clients", Help = "Player(s)" }
    SetXPCommand:AddParam{ Type = "number", Help = "PlayerXP:Integer" }
    SetXPCommand:AddParam{ Type = "number", Help = "CommanderXP:Integer" }
	SetXPCommand:Help( "Set Levels of the specified player(s)" )

    -- ====== Add XP ======
    local function AddXP( Client, Targets, AmountPlayer, AmountCommander )
        local LocalPlayer = Client:GetControllingPlayer()
        for i = 1, #Targets do
            SteamID = tostring(Targets[ i ]:GetUserId())
            Levels:AddPlayerXP( Client:GetControllingPlayer(),
                AmountPlayer )
            Levels:AddCommanderXP( Client:GetControllingPlayer(),
                AmountCommander )

        end
        Levels:SaveLevels()

        self.Notifications:Notify(LocalPlayer, "XP Added")
        self.Notifications:ConsoleMessage( LocalPlayer, "XP Added" )
    end
	local AddXPCommand = Plugin:BindCommand( CommandsFile.AddXP.Console,
        CommandsFile.AddXP.Chat, AddXP )
    AddXPCommand:AddParam{ Type = "clients", Help = "Player(s)" }
    AddXPCommand:AddParam{ Type = "number", Help = "PlayerXP:Integer" }
    AddXPCommand:AddParam{ Type = "number", Help = "CommanderXP:Integer" }
	AddXPCommand:Help( "Adds Levels to the specified player(s), " ..
        "input a negative integer to subtract")

    -- ====== View Levels ======
    local function ViewXP( Client )
        local LocalPlayer = Client:GetControllingPlayer()
        local Summary = Levels:GetSummary( LocalPlayer )
        local PlayerNextLevelFormula =
            Settings.Player.NextLevelFormula.Formula
        local CommanderNextLevelFormula =
            Settings.Commander.NextLevelFormula.Formula

        local PlayerNextLevelFunction =
            loadstring(PlayerNextLevelFormula:gsub("x", Summary.PlayerLevel+1))
        local CommanderNextLevelFunction =
            loadstring(CommanderNextLevelFormula:gsub("x", Summary.CommanderLevel+1))

        local ViewString = "Levels Info for " ..
            Shine.GetClientInfo( Client ) .. "\n" ..
            "Current XP (Player/Commander): " ..
            Summary.PlayerXP ..
            "/" .. Summary.CommanderXP .. "\n" ..
            "Current Level (Player/Commander): " ..
            Summary.PlayerLevel ..
            "/" .. Summary.CommanderLevel .. "\n" ..
            "XP to next level (Player/Commander)" ..
            PlayerNextLevelFunction() ..
            "/" .. CommanderNextLevelFunction()

        self.Notifications:Notify(LocalPlayer, ViewString)
        self.Notifications:ConsoleMessage( LocalPlayer, ViewString )
    end

    local ViewXPCommand = Plugin:BindCommand( CommandsFile.ViewXP.Console,
        CommandsFile.ViewXP.Chat, ViewXP )
    ViewXPCommand:Help( "Show your Levels information" )
end
return Levelling