#pragma semicolon 1

#include <sourcemod>

#define PLUGIN_VERSION "0.1"

new bool:g_bGaveFlag[MAXPLAYERS + 1];
new Handle:g_hDatabase = INVALID_HANDLE;

new String:g_sServerInfo[3][32];

public Plugin:myinfo =
{
	name = "Player Warnings",
	author = "iKill",
	description = "Allows admins to warn a player - 3 strikes; YOU'RE OUT!",
	version = PLUGIN_VERSION,
	url = "http://www.bhslaughter.com"
};

new bool:g_DoColor = true;

#define FEATURE_BAT 1
#define FEATURE_MANI 2

public OnPluginStart()
{
	CreateConVar("sm_warnings_version", PLUGIN_VERSION, "Player Warnings Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	RegAdminCmd("sm_warn", Command_Warnuser, ADMFLAG_GENERIC, "warn <#userid|name> <reason>");
	RegAdminCmd("sm_warnstats", Command_Warnstats, ADMFLAG_GENERIC, "warnstats <#userid|name>");
	
	GetConVarString(FindConVar("ip"), g_sServerInfo[0], sizeof(g_sServerInfo[]));
	GetConVarString(FindConVar("hostport"), g_sServerInfo[1], sizeof(g_sServerInfo[]));
	GetGameFolderName(g_sServerInfo[2], sizeof(g_sServerInfo[]));
	
	AutoExecConfig(true, "tracker");
	
	SQL_CheckConfig("tracker");
	
	SQL_TConnect(sql_Connected);
}

public OnClientPutInServer(client)
{
	g_bGaveFlag[client] = false;
	
	new Handle:hQuery;
	new bool:Found = false;
	new String:Auth[36],String:ClientAuth[36];
	decl String:message[256];
	new String:PlayerName[MAX_NAME_LENGTH];
	new String:WarnAmount[1];
	GetClientName(client, PlayerName, sizeof(PlayerName));
	
	GetClientAuthString(client,ClientAuth,sizeof(ClientAuth));

	hQuery = SQL_Query(g_hDatabase,"SELECT steamid,count FROM bhs_tracker");

	while (SQL_FetchRow(hQuery))
	{
		SQL_FetchString(hQuery,0,Auth,sizeof(Auth));
		if(StrEqual(Auth,ClientAuth,false))
			Found = true;
	}
	
	if (Found)
		{
		Format(message,256,"\x02Warning:\x0F Player %s has %s warnings. Type !warnstats <user> for more info!", PlayerName, WarnAmount);
		SendChatToAdmins(PlayerName, WarnAmount, message);
            {
                if (IsClientInGame(client) && GetUserFlagBits(client)&Admin_Kick)
                {
                    PrintToChat(client,message);
                }
            }
		}

	CloseHandle(hQuery);
}

public Action:Command_Flaguser(client, args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_warn <user>");
		return Plugin_Handled;
	}
	decl String:sText[255], String:sText_Escaped[255],
	     String:sClientName[32], String:sClientName_Escaped[65],
		 String:sAuth[32], String:sMapName[32],
		 String:arg[64];
		 
	new target = FindTarget(client, arg, true, false);
	
	if (target == -1)
		return Plugin_Handled;

	GetCmdArgString(sText, sizeof(sText));
	GetClientName(target, sClientName, sizeof(sClientName));

	SQL_EscapeString(g_hDatabase, sText, sText_Escaped, sizeof(sText_Escaped));
	SQL_EscapeString(g_hDatabase, sClientName, sClientName_Escaped, sizeof(sClientName_Escaped));

	GetClientAuthString(client, sAuth, sizeof(sAuth));
	GetCurrentMap(sMapName, sizeof(sMapName));

	decl String:sQuery[512];
	Format(sQuery, sizeof(sQuery), "INSERT INTO bhs_tracker (name, steamid, serverip, serverport, game) VALUES ('%s', '%s', '%s', '%s', '%s')", sClientName_Escaped, sAuth, sMapName, g_sServerInfo[0], g_sServerInfo[1], g_sServerInfo[2], sText_Escaped);

	new Handle:hQuery = CreateDataPack();
	WritePackString(hQuery, sQuery);

	SendQuery(sQuery);

	ReplyToCommand(client, "\x02[TRACKER] \x0FThe user has been flagged! Thanks!");

	g_bGaveFlag[client] = true;

	return Plugin_Handled;
}

public sql_Connected(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		SetFailState("Database failure: %s", error);
	}
	else
	{
		g_hDatabase = hndl;
	}

	CreateTables();
	SendQuery("SET NAMES 'utf8'");
}

public sql_Query(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		ResetPack(data);

		decl String:query[512];
		ReadPackString(data, query, sizeof(query));


		LogError("Query Failed! %s", error);
		LogError("Query: %s", query);
	}

	CloseHandle(data);
}

stock PrintToAdmins(const String:sMessage[])
{
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            new flags = GetUserFlagBits(i);
            if (CheckAdminFlags(i, ADMFLAG_GENERIC))
            {
                PrintToChat(i, sMessage);
            }
        }
    }
}

/**
 * Checks to see if a client has all of the specified admin flags
 *
 * @param client        Player's index.
 * @param flags            Flags to check for.
 * @return                True on admin having all flags, false otherwise.
 */
stock bool:CheckAdminFlags(client, flags)
{
    new AdminId:admin = GetUserAdmin(client);
    if (admin != INVALID_ADMIN_ID)
    {
        new count, found;
        for (new i = 0; i <= 20; i++)
        {
            if (flags & (1<<i))
            {
                count++;

                if (GetAdminFlag(admin, AdminFlag:i))
                {
                    found++;
                }
            }
        }

        if (count == found)
        {
            return true;
        }
    }

    return false;
}

SendChatToAdmins(String:name[], String:message[])
{
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            if (CheckCommandAccess(i, "sm_chat", ADMFLAG_CHAT))
            {
                if (g_DoColor)
                {
                    PrintToChat(i, "\x04(ADMINS) \x04TRACKER: %s", message);
                }
                else
                {
                    PrintToChat(i, "\x04(TO ADMINS) \x04%s: \x04%s", name, message);
                }
            }
        }    
    }
}


SendQuery(String:query[])
{
	new Handle:dp = CreateDataPack();
	WritePackString(dp, query);
	SQL_TQuery(g_hDatabase, sql_Query, query, dp);
}

CreateTables()
{
	static String:sQuery[] = "\
		CREATE TABLE IF NOT EXISTS `bhs_tracker` ( \
		  `id` int(11) NOT NULL AUTO_INCREMENT, \
		  `name` varchar(65) NOT NULL, \
		  `steamid` varchar(32) NOT NULL, \
		  `map` varchar(32) NOT NULL, \
		  `serverip` varchar(16) NOT NULL, \
		  `serverport` varchar(6) NOT NULL, \
		  `game` varchar(32) NOT NULL, \
		  `feedback` varchar(255) NOT NULL, \
		  `date` timestamp NOT NULL default CURRENT_TIMESTAMP, \
		  PRIMARY KEY (`id`) \
		) ENGINE=MyISAM DEFAULT CHARSET=utf8 AUTO_INCREMENT=1 ;";

	SendQuery(sQuery);
}