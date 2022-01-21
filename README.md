# hookevent

sourcemod plugin allowing arbitrary commands to be executed upon engine events

## Configuration

### Commands

- **sm_hookevent \<event\> "\<command\>"**: execute oneshot command next time the event occurs
- **sm_hookevent_persist \<event\> "\<command\>"**: execute command every time the event occurs
- **sm_hookevent_clear \<event\>"**: remove all hooks for the event
