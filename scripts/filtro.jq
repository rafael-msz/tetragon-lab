(.process_exec // .process_exit // .process_kprobe) as $e
| select($e != null)
| ($e.process) as $p
| select( ($p.binary // "") | test("/runc$|/proc/self/fd/|docker-init|containerd|/systemd$|unix_chkpwd|/sudo$|/sleep$|/docker$|/tetra$|getevents") | not )
| ( ($p.cap.permitted // []) + ($p.cap.effective // []) ) as $caps
| ( ($p.docker != null) and ($p.ns.mnt.is_host == true) ) as $escapou
| {
    hora:       .time[11:19],
    tipo:       (if .process_exec then "exec" elif .process_exit then "exit" else "kprobe" end),
    cont:       (($p.docker // "")[0:12] | if . == "" then "host" else . end),
    politica:   (.process_kprobe.policy_name // null),       # só em kprobe — a detecção de fato
    hook:       (.process_kprobe.function_name // null),
    processo:   $p.binary,
    cmd:        $p.arguments,
    evidencia:  [ .process_kprobe.args[]? | (.file_arg.path // .string_arg // (if .sock_arg then (.sock_arg.daddr + ":" + ((.sock_arg.dport // 0)|tostring)) else empty end) // (.int_arg|tostring)) ],
    saida:      (.process_exit.status // null),               # 137 = morto por SIGKILL (contenção)
    uid:        ($p.process_credentials.uid // $p.uid // null),
    isolamento: ( if   $p.docker == null          then "host"
                  elif $escapou                    then "ESCAPE->HOST"
                  elif ($p.ns.mnt.inum != null)    then "contido"
                  else "n/d" end ),
    sinais:     [ (if $escapou                           then "🚨ESCAPE->HOST"  else empty end),
                  (if ($p.docker != null and ($caps | index("CAP_SYS_ADMIN"))) then "🛑CAP_SYS_ADMIN" else empty end),
                  (if ($p.docker != null and $p.in_init_tree == false)         then "⚠injetado"      else empty end) ]
  }
