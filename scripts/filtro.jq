fromjson?
| (.process_exec // .process_exit // .process_kprobe) as $e
| select($e != null)
| select( ($e.process.binary // "") | test("/runc$|containerd|/systemd$|unix_chkpwd|/sudo$|/sleep$|/docker$|/tetra$|getevents") | not )
| ( .time[11:19] ) as $t
| ( if .process_exec then "exec" elif .process_exit then "exit" else "kprb" end ) as $tipo
| ( ($e.process.docker // "")[0:12] | if . == "" then "host" else . end ) as $loc
| ( if .process_kprobe then ((.process_kprobe.policy_name // "-") + ":" + (.process_kprobe.function_name // "-"))
    elif .process_exit then ("exit=" + ((.process_exit.status // 0) | tostring))
    else "-" end ) as $lbl
| ( if (.process_kprobe.process.ns.mnt.is_host == true) then " [ESCAPE->HOST]" else "" end ) as $esc
| ( (($e.process.binary // "") + " " + ($e.process.arguments // ""))[0:72] ) as $cmd
| "\($t)  \($tipo)  \($loc)  \($lbl)\($esc)  \($cmd)"
