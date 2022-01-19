#include <sourcemod>
#include <adt_trie>

StringMap HookMap;

#pragma newdecls required

public Plugin myinfo =
{
    name = "hookevent",
    author = "tmick0",
    description = "Allows arbitrary commands to be executed at arbitrary events",
    version = "0.1",
    url = "github.com/tmick0/sm_hookevent"
};

#define CMD_HOOKEVENT "sm_hookevent"

public void OnPluginStart() {
    RegAdminCmd(CMD_HOOKEVENT, CmdHookEvent, ADMFLAG_GENERIC, "add an event hook");
    HookMap = new StringMap();
}

Action CmdHookEvent(int client, int argc) {
    if (argc != 2) {
        LogMessage("wrong number of arguments to %s", CMD_HOOKEVENT);
        return Plugin_Handled;
    }

    char event[128];
    char command[1024];

    if (GetCmdArg(1, event, sizeof(event)) <= 0 || GetCmdArg(2, command, sizeof(command)) <= 0) {
        LogMessage("argument parsing failure");
        return Plugin_Handled;
    }

    HookMap.SetString(event, command, true);
    HookEvent(event, OnEvent);
    
    return Plugin_Handled;
}

Action OnEvent(Event event, const char[] name, bool dontBroadcast) {
    char command[1024];
    if (HookMap.GetString(name, command, sizeof(command))) {
        HookMap.Remove(name);
        UnhookEvent(name, OnEvent);
        ServerCommand(command);
    }
}
