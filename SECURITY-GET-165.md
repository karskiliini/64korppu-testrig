# GET-165

The --stop-on pattern was interpolated inside an SSH command without escaping embedded apostrophes. A pattern could become remote shell syntax instead of literal monitor input. Every dynamic argument is now POSIX shell quoted. The regression records fake SSH commands and confirms the adversarial pattern remains one literal argument; it fails against the original script.

No real SSH connection, firmware copy, flashing or hardware monitoring was performed. Existing Tailscale/SSH authentication configuration is preserved.
