import json, os, pathlib, shutil, subprocess, tempfile, unittest

class DeployArguments(unittest.TestCase):
    def test_monitor_pattern_is_one_literal_remote_argument(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp); scripts=root/'project/tools/testrig'; scripts.mkdir(parents=True)
            shutil.copy(pathlib.Path(__file__).parents[1]/'deploy.sh',scripts/'deploy.sh')
            firmware=root/'project/firmware/E-IEC-Nano-SRAM';firmware.mkdir(parents=True)
            (firmware/'64korppu_nano.hex').write_text('test-only')
            bindir=root/'bin';bindir.mkdir();log=root/'commands.jsonl'
            (bindir/'scp').write_text('#!/bin/sh\nexit 0\n')
            (bindir/'ssh').write_text('#!/usr/bin/env python3\nimport os,sys,json,shlex\nwith open(os.environ["TEST_COMMAND_LOG"],"a") as f:f.write(json.dumps(shlex.split(sys.argv[2]))+"\\n")\n')
            for p in bindir.iterdir():p.chmod(0o755)
            payload="ready'; touch injected; echo '"
            env=dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH'],TEST_COMMAND_LOG=str(log))
            subprocess.run(['bash',str(scripts/'deploy.sh'),'--no-build','--monitor','--stop-on',payload],env=env,check=True,capture_output=True)
            # A malicious quote must neither split arguments nor add shell commands.
            records=[json.loads(x) for x in log.read_text().splitlines() if x]
            self.assertEqual(records[-1],['~/tools/monitor.py','--timeout','30','--stop-on',payload])

if __name__=='__main__':unittest.main()
