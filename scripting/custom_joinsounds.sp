#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <multicolors>

#define MAX_JNAME_LENGTH 64
#define MAX_VOLUME_LENGTH 6
#define MAX_FLAGS_LENGTH 21
#define MAX_PATH_LENGTH PLATFORM_MAX_PATH + 1

#define LoopValidClients(%1) for(int %1 = 1; %1 <= MaxClients; %1++) if(IsClientValid(%1))

StringMap g_smFiles = null;
StringMap g_smVolume = null;
StringMap g_smFlags = null;

Handle g_hCookie = null;
char g_sName[MAXPLAYERS + 1][MAX_JNAME_LENGTH];

public Plugin myinfo =
{
    name = "Custom Joinsounds",
    author = "Bara",
    description = "",
    version = "1.0.0",
    url = "github.com/Bara"
};

public void OnPluginStart()
{
    g_hCookie = RegClientCookie("custom_joinsounds_t1", "Custom Joinsounds", CookieAccess_Private);

    RegConsoleCmd("sm_joinsounds", Command_Joinsounds);

    HookEvent("player_spawn", Event_PlayerSpawn);

    LoopValidClients(i)
    {
        if (!AreClientCookiesCached(i))
        {
            continue;
        }

        OnClientCookiesCached(i);
    }
}

public void OnMapStart()
{
    LoadJoinsounds();
}

public void OnClientCookiesCached(int client)
{
    if (IsFakeClient(client))
    {
        return;
    }

    GetClientCookie(client, g_hCookie, g_sName[client], sizeof(g_sName[]));
}

public void OnClientPostAdminCheck(int client)
{
    if (IsFakeClient(client))
    {
        return;
    }

    if (strlen(g_sName[client]) > 0)
    {
        char sFile[MAX_PATH_LENGTH];
        g_smFiles.GetString(g_sName[client], sFile, sizeof(sFile));

        char sVolume[MAX_VOLUME_LENGTH];
        g_smVolume.GetString(g_sName[client], sVolume, sizeof(sVolume));

        float fVolume = StringToFloat(sVolume);

        EmitSoundToClient(client, sFile, _, _, _, _, fVolume);
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!IsClientValid(client))
    {
        return;
    }

    if (strlen(g_sName[client]) < 1)
    {
        CPrintToChat(client, "{green}You haven't selected an joinsound. Type {darkred}!joinsounds {green} to select an joinsound.");
    }
}

public Action Command_Joinsounds(int client, int args)
{
    if (!IsClientValid(client))
    {
        return Plugin_Handled;
    }

    ListJoinsounds(client);

    return Plugin_Handled;
}

void ListJoinsounds(int client)
{
    Menu menu = new Menu(Menu_JoinsoundList);
    menu.SetTitle("Select joinsound:");

    StringMapSnapshot smFlags = g_smFlags.Snapshot();

    for (int i = 0; i < smFlags.Length; i++)
    {
        char sName[MAX_JNAME_LENGTH];
        char sFlags[MAX_FLAGS_LENGTH];

        smFlags.GetKey(i, sName, sizeof(sName));
        g_smFlags.GetString(sName, sFlags, sizeof(sFlags));

        int iFlags = ReadFlagString(sFlags);
        if (!CheckCommandAccess(client, "joinsound_access", iFlags, true))
        {
            menu.AddItem("", sName, ITEMDRAW_DISABLED);
            continue;
        }

        if (StrEqual(sName, g_sName[client]))
        {
            menu.AddItem("", sName, ITEMDRAW_DISABLED);
        }
        else
        {
            menu.AddItem(sName, sName);
        }
    }

    delete smFlags;

    menu.ExitBackButton = false;
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Menu_JoinsoundList(Menu menu, MenuAction action, int client, int param)
{
    if (action == MenuAction_Select)
    {
        menu.GetItem(param, g_sName[client], sizeof(g_sName[]));
        SetClientCookie(client, g_hCookie, g_sName[client]);
        CPrintToChat(client, "{green}You've selected {darkred}%s {green}as your new joinsound.", g_sName[client]);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
}

void LoadJoinsounds()
{
    delete g_smFiles;
    delete g_smVolume;
    delete g_smFlags;

    g_smFiles = new StringMap();
    g_smVolume = new StringMap();
    g_smFlags = new StringMap();

    char sFile[MAX_PATH_LENGTH];
    BuildPath(Path_SM, sFile, sizeof(sFile), "configs/custom_joinsounds.ini");

    KeyValues kvJoinsounds = new KeyValues("Custom-Joinsounds");

    if (!kvJoinsounds.ImportFromFile(sFile))
    {
        SetFailState("[Custom-Joinsounds] Can't read \"%s\"! (ImportFromFile)", sFile);
        delete kvJoinsounds;
        return;
    }

    if (!kvJoinsounds.GotoFirstSubKey())
    {
        SetFailState("[Custom-Joinsounds] Can't read \"%s\" correctly! (GotoFirstSubKey)", sFile);
        delete kvJoinsounds;
        return;
    }

    do
    {
        char sName[MAX_JNAME_LENGTH];
        char sJFile[MAX_PATH_LENGTH];
        char sVolume[MAX_VOLUME_LENGTH];
        char sFlags[MAX_FLAGS_LENGTH];

        kvJoinsounds.GetSectionName(sName, sizeof(sName));

        kvJoinsounds.GetString("file", sJFile, sizeof(sJFile));

        char sBuffer[MAX_PATH_LENGTH];
        Format(sBuffer, sizeof(sBuffer), "sound/%s", sJFile);

        if (!FileExists(sBuffer))
        {
            SetFailState("[Custom-Joinsounds] Can't find the joinsound file for \"%s\" (\"%s\")! (FileExists)", sName, sJFile);
            delete kvJoinsounds;
            return;
        }

        if (!PrecacheSound(sJFile))
        {
            SetFailState("[Custom-Joinsounds] Can't precache the joinsound \"%s\" (\"%s\") correctly! (PrecacheSound)", sName, sJFile);
            delete kvJoinsounds;
            return;
        }

        AddFileToDownloadsTable(sBuffer);

        kvJoinsounds.GetString("volume", sVolume, sizeof(sVolume));
        kvJoinsounds.GetString("flags", sFlags, sizeof(sFlags));

        g_smFiles.SetString(sName, sJFile, true);
        g_smVolume.SetString(sName, sVolume, true);
        g_smFlags.SetString(sName, sFlags, true);

        LogMessage("[Custom-Joinsounds] Name: %s, File: %s, Volume: %s, Flags: %s", sName, sJFile, sVolume, sFlags);
    }
    while (kvJoinsounds.GotoNextKey(false));
    
    delete kvJoinsounds;
}

bool IsClientValid(int client)
{
    if (client > 0 && client <= MaxClients)
    {
        if(IsClientInGame(client) && !IsFakeClient(client) && !IsClientSourceTV(client))
        {
            return true;
        }
    }

    return false;
}
