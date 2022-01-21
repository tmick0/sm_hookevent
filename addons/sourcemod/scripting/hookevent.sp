#include <sourcemod>
#include <adt_trie>
#include <adt_array>

#pragma newdecls required

public Plugin myinfo =
{
    name = "hookevent",
    author = "tmick0",
    description = "Allows arbitrary commands to be executed at arbitrary events",
    version = "0.2",
    url = "github.com/tmick0/sm_hookevent"
};

#define CMD_HOOKEVENT "sm_hookevent"
#define CMD_HOOKEVENTPERSIST "sm_hookevent_persist"
#define CMD_HOOKEVENTCLEAR "sm_hookevent_clear"

#define CVAR_DEBUG "sm_hookevent_debug"

#define EVENT_LEN 128
#define COMMAND_LEN 512

#define MAX_HOOKS_PER_EVENT 16
#define MAX_HOOKS_GLOBAL 128

#define ERR_TOO_MANY_HOOKS_FOR_EVENT -1
#define ERR_TOO_MANY_HOOKS_GLOBAL -2
#define ERR_ARGPARSE -3

bool HookSlotValid[MAX_HOOKS_GLOBAL];
bool HookSlotPersist[MAX_HOOKS_GLOBAL];
char HookSlotCommand[MAX_HOOKS_GLOBAL][COMMAND_LEN];
StringMap HookMap;
int Debug;

ConVar CvarDebug;

public void OnPluginStart() {
    HookMap = new StringMap();
    for (int i = 0; i < MAX_HOOKS_GLOBAL; ++i) {
        HookSlotValid[i] = false;
    }

    RegAdminCmd(CMD_HOOKEVENT, CmdHookEvent, ADMFLAG_GENERIC, "add a one-shot event hook");
    RegAdminCmd(CMD_HOOKEVENTPERSIST, CmdHookEventPersist, ADMFLAG_GENERIC, "add a persistent event hook");
    RegAdminCmd(CMD_HOOKEVENTCLEAR, CmdHookEventClear, ADMFLAG_GENERIC, "remove all hooks associated with an event");
    CvarDebug = CreateConVar(CVAR_DEBUG, "0", "enable debug output");
    Debug = CvarDebug.IntValue;
    HookConVarChange(CvarDebug, UpdateDebugFlag);
}

void UpdateDebugFlag(ConVar cvar, const char[] oldval, const char[] newval) {
    Debug = CvarDebug.IntValue;
}

// get the next available global hook slot
int GetNextSlot() {
    for (int i = 0; i < MAX_HOOKS_GLOBAL; ++i) {
        if (!HookSlotValid[i]) {
            return i;
        }
    }
    return ERR_TOO_MANY_HOOKS_GLOBAL;
}

// fetch or initialize an event slot array and get the next available index in it
void GetHookIndices(const char[] event, int[] indices, int& idx, bool& is_new) {
    if (HookMap.GetArray(event, indices, MAX_HOOKS_PER_EVENT)) {
        is_new = false;
        if (Debug) {
            LogMessage("retrieving existing slots for event <%s>", event);
        }
        for (int i = 0; i < MAX_HOOKS_PER_EVENT; ++i) {
            if (indices[i] < 0) {
                idx = i;
                return;
            }
        }
        idx = ERR_TOO_MANY_HOOKS_FOR_EVENT;
    }
    else {
        is_new = true;
        if (Debug) {
            LogMessage("initializing slots for event <%s>", event);
        }
        for (int i = 0; i < MAX_HOOKS_PER_EVENT; ++i) {
            indices[i] = -1;
        }
        idx = 0;
    }
}

// populates a slot and assigns it to the event
int AddHook(const char[] event, const char[] command, bool persist) {
    // get the slot array for this hook and find the next available index
    int slots[MAX_HOOKS_PER_EVENT];
    int idx;
    bool is_new;
    GetHookIndices(event, slots, idx, is_new);
    if (idx < 0) {
        return idx;
    }

    // get the next global slot available
    int slot = GetNextSlot();
    if (slot < 0) {
        return slot;
    }

    if (Debug) {
        LogMessage("adding hook for event <%s> in index %d slot %d", event, idx, slot);
    }

    // populate the slot
    slots[idx] = slot;
    strcopy(HookSlotCommand[slot], COMMAND_LEN, command);
    HookSlotPersist[slot] = persist;
    HookSlotValid[slot] = true;

    HookMap.SetArray(event, slots, MAX_HOOKS_PER_EVENT, true);
    if (is_new) {
        HookEvent(event, OnEvent, EventHookMode_PostNoCopy);
    }
    return 0;
}

Action CmdHookEvent(int client, int argc) {
    if (argc != 2) {
        HandleError(client, ERR_ARGPARSE);
        return Plugin_Handled;
    }

    char event[EVENT_LEN];
    char command[COMMAND_LEN];
    if (GetCmdArg(1, event, sizeof(event)) <= 0 || GetCmdArg(2, command, sizeof(command)) <= 0) {
        HandleError(client, ERR_ARGPARSE);
        return Plugin_Handled;
    }

    int err = AddHook(event, command, false);
    if (err) {
        HandleError(client, err);
    }

    return Plugin_Handled;
}

Action CmdHookEventPersist(int client, int argc) {
    if (argc != 2) {
        HandleError(client, ERR_ARGPARSE);
        return Plugin_Handled;
    }

    char event[EVENT_LEN];
    char command[COMMAND_LEN];
    if (GetCmdArg(1, event, sizeof(event)) <= 0 || GetCmdArg(2, command, sizeof(command)) <= 0) {
        HandleError(client, ERR_ARGPARSE);
        return Plugin_Handled;
    }

    int err = AddHook(event, command, true);
    if (err) {
        HandleError(client, err);
    }

    return Plugin_Handled;
}

Action CmdHookEventClear(int client, int argc) {
    if (argc != 1) {
        HandleError(client, ERR_ARGPARSE);
        return Plugin_Handled;
    }

    char event[EVENT_LEN];
    if (GetCmdArg(1, event, sizeof(event)) <= 0) {
        HandleError(client, ERR_ARGPARSE);
        return Plugin_Handled;
    }

    int slots[MAX_HOOKS_PER_EVENT];
    int idx;
    bool is_new;
    GetHookIndices(event, slots, idx, is_new);
    for (int i = 0; i < MAX_HOOKS_PER_EVENT; ++i) {
        int slot = slots[i];
        if (slot >= 0) {
            if (Debug) {
                LogMessage("unmapping event <%s> hook index %d slot %d", event, i, slot);
            }
            HookSlotValid[slot] = false;
        }
    }

    HookMap.Remove(event);
    if (!is_new) {
        UnhookEvent(event, OnEvent);
    }
    return Plugin_Handled;
}

int ExecuteSlots(int[] slots) {
    int hooks_remaining = 0;
    for (int i = 0; i < MAX_HOOKS_PER_EVENT; ++i) {
        int slot = slots[i];
        if (slot >= 0) {
            if (HookSlotValid[slot]) {
                if (Debug) {
                    LogMessage("executing hook index %d slot %d", i, slot);
                }
                ServerCommand(HookSlotCommand[slot]);
                if (HookSlotPersist[slot]) {
                    ++hooks_remaining;
                }
                else {
                    HookSlotValid[slot] = false;
                    slots[i] = -1;
                }
            }
            else {
                LogMessage("ERROR: attempted to execute a slot which was not valid, state has gotten inconsistent");
            }
        }
    }
    return hooks_remaining;
}

Action OnEvent(Event event, const char[] name, bool dontBroadcast) {
    int slots[MAX_HOOKS_PER_EVENT];
    if (Debug) {
        LogMessage("received event <%s>", name);
    }

    if (!HookMap.GetArray(name, slots, MAX_HOOKS_PER_EVENT)) {
        LogMessage("ERROR: received a trigger from event <%s> which is not registered", name);
        return Plugin_Continue;
    }

    if (ExecuteSlots(slots)) {
        HookMap.SetArray(name, slots, MAX_HOOKS_PER_EVENT, true);
    }
    else {
        if (Debug) {
            LogMessage("event <%s> has no remaining hooks", name);
        }
        UnhookEvent(name, OnEvent);
        HookMap.Remove(name);
    }

    return Plugin_Continue;
}

void HandleError (int client, int error) {
    if (error == ERR_TOO_MANY_HOOKS_FOR_EVENT) {
        ReplyToCommand(client, "There are already the maximum number of hooks assigned to this event");
    }
    else if (error == ERR_TOO_MANY_HOOKS_GLOBAL) {
        ReplyToCommand(client, "There are already the maximum number of hooks registered");
    }
    else if (error == ERR_ARGPARSE) {
        ReplyToCommand(client, "Could not understand the command, check the syntax and try again");
    }
    else {
        ReplyToCommand(client, "An unknown error occurred");
    }
}
