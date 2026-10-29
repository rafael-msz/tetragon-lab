select(.process_kprobe)
| select(.process_kprobe.process.docker != null)
| {
    hora:      .time[11:19],
    cont:      .process_kprobe.process.docker[0:12],
    politica:  .process_kprobe.policy_name,
    hook:      .process_kprobe.function_name,
    processo:  .process_kprobe.process.binary,
    cmd:       .process_kprobe.process.arguments,
    evidencia: [ .process_kprobe.args[]? | (.file_arg.path // .string_arg // (if .sock_arg then (.sock_arg.daddr + ":" + ((.sock_arg.dport // 0)|tostring)) else null end) // (.int_arg|tostring)) ],
    uid:       .process_kprobe.process.process_credentials.uid,
    escape:    (.process_kprobe.process.ns.mnt.is_host == true)
  }
