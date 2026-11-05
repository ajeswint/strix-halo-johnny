#!/bin/bash
# rock-box only. Rotate Intel DMT Console auth.jwtKey and auth.adminPassword.
# Does not print either value. Does not talk to Johnny. No sudo.
# AJ paste (no arguments):
#   bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-6-dmt-rotate.sh
# Rollback, console stopped:
#   bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-6-dmt-rotate.sh --restore
# After a successful login proof, delete the backups:
#   bash /home/aj/Projects/strix-halo-johnny/docs/tool-install/step-6-dmt-rotate.sh --shred-backup
# Repo check (not the AJ paste):
#   bash docs/tool-install/step-6-dmt-rotate.sh --self-test
# Docs: docs/tool-install/step-6-amt-power.md

set -euo pipefail
umask 077

mode="${1:-}"
case "$mode" in
  "") mode=rotate ;;
  --restore) mode=restore ;;
  --shred-backup) mode=shred ;;
  --self-test) mode=self-test ;;
  *)
    echo STOP-usage
    exit 2
    ;;
esac

if [[ "$(id -u)" -eq 0 ]]; then
  echo STOP-root
  exit 1
fi

if [[ "$mode" != "self-test" ]]; then
  hn=$(hostname)
  hn_lc=${hn,,}
  case "$hn_lc" in
    johnny|johnny.*)
      echo "STOP-host $hn"
      exit 1
      ;;
  esac
  if ! command -v ip >/dev/null 2>&1; then
    echo STOP-no-ip
    exit 1
  fi
  if ! ip -4 -o addr show | grep -q 'inet 192.168.51.2/'; then
    echo STOP-not-rock-box
    exit 1
  fi
  if [[ -n "${STEP6_CONFIG+x}" || -n "${STEP6_MODE+x}" ]]; then
    echo STOP-env
    exit 1
  fi
  echo "HOST $hn"
  echo ADDR-OK
  export STEP6_CONFIG=/home/aj/dmt-console/dist/linux/config/config.yml
fi

export STEP6_MODE="$mode"

if ! command -v python3 >/dev/null 2>&1; then
  echo STOP-no-python3
  exit 1
fi

python3 - <<'PY'
import base64
import contextlib
import errno
import io
import os
import re
import secrets
import shutil
import stat
import string
import subprocess
import tempfile
import time
from pathlib import Path

REAL_CONFIG = Path("/home/aj/dmt-console/dist/linux/config/config.yml")
POINTER_NAME = "step6-backup-path.txt"
BACKUP_NAME = re.compile(r"^config\.yml\.bak-step6-\d{14}$")
KEY_LINE = {
    "adminPassword": re.compile(
        r"^([ \t]*)adminPassword:[ \t]*([^ \t#\r\n]+)[ \t]*(\r?\n)?$"
    ),
    "jwtKey": re.compile(
        r"^([ \t]*)jwtKey:[ \t]*([^ \t#\r\n]+)[ \t]*(\r?\n)?$"
    ),
    "adminUsername": re.compile(
        r"^([ \t]*)adminUsername:[ \t]*([A-Za-z0-9._-]+)[ \t]*(\r?\n)?$"
    ),
}
ALPHABET = string.ascii_letters + string.digits


def stop(token):
    print(token)
    raise SystemExit(1)


def umask_private():
    os.umask(0o077)


def table_has_listen(text, port):
    needle = "%04X" % port
    for i, line in enumerate(text.splitlines()):
        if i == 0 and line.lower().startswith("sl"):
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        local = parts[1].rsplit(":", 1)[-1].upper()
        if parts[3] == "0A" and local == needle:
            return True
    return False


def port_listening(port):
    found_any = False
    for name in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            text = Path(name).read_text(encoding="utf-8")
        except FileNotFoundError:
            continue
        found_any = True
        if table_has_listen(text, port):
            return True
    if not found_any:
        stop("STOP-no-proc-net")
    return False


def ensure_console_down(check_port):
    if check_port and port_listening(8181):
        stop("STOP-console-up")


def inside_git(parent):
    try:
        result = subprocess.run(
            ["git", "-C", str(parent), "rev-parse", "--is-inside-work-tree"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            universal_newlines=True,
        )
    except FileNotFoundError:
        stop("STOP-no-git")
    return result.returncode == 0 and result.stdout.strip() == "true"


def guard_path(cfg, real_mode):
    if "strix-halo-johnny" in cfg.parts:
        stop("STOP-repo-path")
    if inside_git(cfg.parent):
        stop("STOP-git")
    if real_mode and cfg != REAL_CONFIG:
        stop("STOP-path")


def read_nofollow(path):
    try:
        fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as exc:
        if exc.errno == errno.ELOOP:
            stop("STOP-symlink")
        if exc.errno == errno.ENOENT:
            stop("STOP-no-config")
        stop("STOP-read")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            stop("STOP-not-file")
        if st.st_size > 1000000:
            stop("STOP-size")
        return os.read(fd, st.st_size)
    finally:
        os.close(fd)


def write_all(fd, data):
    view = data
    while view:
        n = os.write(fd, view)
        if n <= 0:
            stop("STOP-write")
        view = view[n:]


def write_replace(path, data):
    if path.is_symlink():
        stop("STOP-symlink")
    parent = path.parent
    tmp = parent / (path.name + ".tmp-step6")
    if tmp.exists() or tmp.is_symlink():
        stop("STOP-tmp-exists")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(str(tmp), flags, 0o600)
    try:
        write_all(fd, data)
        os.fsync(fd)
    except SystemExit:
        os.close(fd)
        try:
            os.unlink(str(tmp))
        except OSError:
            pass
        raise
    except Exception:
        os.close(fd)
        try:
            os.unlink(str(tmp))
        except OSError:
            pass
        stop("STOP-write")
    os.close(fd)
    os.replace(str(tmp), str(path))
    os.chmod(str(path), 0o600)
    dirfd = os.open(str(parent), os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(dirfd)
    finally:
        os.close(dirfd)


def write_new_file(path, data):
    if path.exists() or path.is_symlink():
        stop("STOP-backup-exists")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(str(path), flags, 0o600)
    try:
        write_all(fd, data)
        os.fsync(fd)
    except SystemExit:
        os.close(fd)
        raise
    except Exception:
        os.close(fd)
        stop("STOP-write")
    os.close(fd)
    os.chmod(str(path), 0o600)


def find_key(lines, key):
    found = []
    for i, line in enumerate(lines):
        if KEY_LINE[key].match(line):
            found.append(i)
    return found


def unquote(raw):
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in ("'", '"'):
        return raw[1:-1]
    return raw


def value_of(line, key):
    match = KEY_LINE[key].match(line)
    if match is None:
        stop("STOP-line-shape")
    return unquote(match.group(2))


def decode_config(data):
    if data.startswith(b"\xef\xbb\xbf") or b"\x00" in data:
        stop("STOP-encoding")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        stop("STOP-encoding")
    return text.splitlines(keepends=True)


def require_one(lines, key):
    found = find_key(lines, key)
    if len(found) != 1:
        stop("STOP-count-" + key)
    return found[0]


def new_password():
    return "".join(secrets.choice(ALPHABET) for _ in range(16))


def new_jwt():
    token = base64.b64encode(secrets.token_bytes(32)).decode("ascii")
    if len(token) != 44 or token.startswith("="):
        stop("STOP-jwt-gen")
    return token


def format_line(match, key, value):
    nl = match.group(3) or ""
    return '%s%s: "%s"%s' % (match.group(1), key, value, nl)


def read_pointer(parent):
    pointer = parent / POINTER_NAME
    if not pointer.exists() and not pointer.is_symlink():
        return None
    if pointer.is_symlink():
        stop("STOP-pointer-symlink")
    text = pointer.read_text(encoding="utf-8")
    name = text.strip()
    if BACKUP_NAME.fullmatch(name) is None or "/" in name or name != text.strip():
        stop("STOP-pointer")
    if text != name + "\n":
        stop("STOP-pointer")
    dest = parent / name
    if dest.is_symlink() or not dest.is_file():
        stop("STOP-pointer-target")
    return dest


def write_pointer(parent, backup):
    pointer = parent / POINTER_NAME
    if pointer.exists() or pointer.is_symlink():
        return read_pointer(parent)
    payload = backup.name + "\n"
    write_new_file(pointer, payload.encode("ascii"))
    return backup


def rotate(cfg, check_port):
    umask_private()
    ensure_console_down(check_port)
    guard_path(cfg, check_port)
    original = read_nofollow(cfg)
    lines = decode_config(original)
    pw_i = require_one(lines, "adminPassword")
    jwt_i = require_one(lines, "jwtKey")
    user_i = require_one(lines, "adminUsername")
    old_pw = value_of(lines[pw_i], "adminPassword")
    old_jwt = value_of(lines[jwt_i], "jwtKey")
    if len(old_pw) != 16 or len(old_jwt) != 44:
        stop("STOP-length")
    if '"' in old_pw or '"' in old_jwt or "\\" in old_pw or "\\" in old_jwt:
        stop("STOP-shape")
    password = new_password()
    jwt = new_jwt()
    tries = 0
    while (password == old_pw or jwt == old_jwt or password == jwt) and tries < 3:
        password = new_password()
        jwt = new_jwt()
        tries += 1
    if password == old_pw or jwt == old_jwt or len(password) != 16 or len(jwt) != 44:
        stop("STOP-gen")
    pw_match = KEY_LINE["adminPassword"].match(lines[pw_i])
    jwt_match = KEY_LINE["jwtKey"].match(lines[jwt_i])
    new_lines = list(lines)
    new_lines[pw_i] = format_line(pw_match, "adminPassword", password)
    new_lines[jwt_i] = format_line(jwt_match, "jwtKey", jwt)
    updated = "".join(new_lines).encode("utf-8")
    if updated == original:
        stop("STOP-unchanged")
    backup = None
    for _ in range(5):
        stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
        candidate = cfg.parent / ("config.yml.bak-step6-" + stamp)
        if not candidate.exists() and not candidate.is_symlink():
            backup = candidate
            break
        time.sleep(1.1)
    if backup is None:
        stop("STOP-backup-exists")
    write_new_file(backup, original)
    if read_nofollow(backup) != original:
        stop("STOP-backup-mismatch")
    rollback = write_pointer(cfg.parent, backup)
    write_replace(cfg, updated)
    written = decode_config(read_nofollow(cfg))
    if value_of(written[pw_i], "adminPassword") != password:
        stop("STOP-verify")
    if value_of(written[jwt_i], "jwtKey") != jwt:
        stop("STOP-verify")
    if find_key(written, "adminPassword") != [pw_i] or find_key(written, "jwtKey") != [jwt_i]:
        stop("STOP-verify")
    mode = os.stat(str(cfg)).st_mode & 0o777
    print("ROTATE-OK")
    print("BACKUP " + str(backup))
    print("ROLLBACK " + str(rollback))
    print("ADMIN-USER " + value_of(lines[user_i], "adminUsername"))
    print("ADMIN-PASSWORD-LEN %d" % len(password))
    print("JWTKEY-LEN %d" % len(jwt))
    print("CONFIG-MODE %o" % mode)
    del password, jwt, old_pw, old_jwt


def restore(cfg, check_port):
    umask_private()
    ensure_console_down(check_port)
    guard_path(cfg, check_port)
    if cfg.is_symlink():
        stop("STOP-symlink")
    dest = read_pointer(cfg.parent)
    if dest is None:
        stop("STOP-no-backup")
    data = read_nofollow(dest)
    lines = decode_config(data)
    require_one(lines, "adminPassword")
    require_one(lines, "jwtKey")
    require_one(lines, "adminUsername")
    write_replace(cfg, data)
    if read_nofollow(cfg) != data:
        stop("STOP-verify")
    print("RESTORE-OK")
    print("RESTORED-FROM " + dest.name)


def matching_backups(parent):
    found = []
    for child in parent.iterdir():
        if child.is_symlink():
            continue
        if BACKUP_NAME.fullmatch(child.name) and child.is_file():
            found.append(child)
    return found


def shred_file(path):
    try:
        result = subprocess.run(["shred", "-u", str(path)])
    except FileNotFoundError:
        stop("STOP-no-shred")
    if result.returncode != 0:
        stop("STOP-shred")


def shred(cfg, check_port):
    umask_private()
    ensure_console_down(check_port)
    guard_path(cfg, check_port)
    parent = cfg.parent
    names = matching_backups(parent)
    pointer = parent / POINTER_NAME
    pointer_exists = pointer.exists() or pointer.is_symlink()
    if pointer.is_symlink():
        stop("STOP-pointer-symlink")
    if not names and not pointer_exists:
        stop("STOP-no-backup")
    for child in names:
        shred_file(child)
    if pointer_exists:
        shred_file(pointer)
    print("SHRED-OK %d" % len(names))


def capture(fn):
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            fn()
    except SystemExit as exc:
        return exc.code, buf.getvalue()
    return 0, buf.getvalue()


def expect_stop(fn, token):
    code, text = capture(fn)
    if code != 1 or token not in text.split():
        safe = [ln for ln in text.splitlines() if ln.startswith("STOP-") and "CANARY" not in ln]
        print("SELF-TEST-SAW " + " ".join(safe))
        stop("STOP-self-test-message")


def self_test():
    umask_private()
    header = "  sl  local_address\n"
    listen = header + "   0: 00000000:1FF5 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 1 1\n"
    quiet = header + "   0: 00000000:1FF5 00000000:0000 01 00000000:00000000 00:00000000 00000000     0        0 1 1\n"
    if not table_has_listen(listen, 8181) or table_has_listen(quiet, 8181):
        stop("STOP-self-test-listen")
    if table_has_listen(listen, 3000):
        stop("STOP-self-test-listen")

    old_pw = "CANARYPASSWORDxx"
    old_jwt = "CANARYJWTKEYCANARYJWTKEYCANARYJWTKEYCANARYJ="
    if len(old_pw) != 16 or len(old_jwt) != 44:
        stop("STOP-self-test-fixture")
    body = (
        "app:\n"
        "  encryption_key: \"\"\n"
        "auth:\n"
        "  adminUsername: standalone\n"
        "  adminPassword: %s\n"
        "  jwtKey: %s\n"
        "  jwtExpiration: 24h0m0s\n"
        "ea:\n"
        "  password: keep-this-ea\n"
    ) % (old_pw, old_jwt)

    tmp = Path(tempfile.mkdtemp(prefix="step6-self-test-"))
    cfg = tmp / "config.yml"
    cfg.write_text(body, encoding="utf-8")
    os.chmod(str(cfg), 0o644)

    code, text = capture(lambda: rotate(cfg, False))
    if code != 0 or "ROTATE-OK" not in text.splitlines():
        stop("STOP-self-test-rotate")
    if "CANARY" in text or old_pw in text or old_jwt in text:
        stop("STOP-self-test-leaked")
    written = cfg.read_text(encoding="utf-8")
    if old_pw in written or old_jwt in written:
        stop("STOP-self-test-same")
    if "keep-this-ea" not in written or "jwtExpiration: 24h0m0s" not in written:
        stop("STOP-self-test-other-field")
    if "encryption_key:" not in written:
        stop("STOP-self-test-other-field")
    new_lines = written.splitlines(keepends=True)
    pw = value_of(new_lines[find_key(new_lines, "adminPassword")[0]], "adminPassword")
    jwt = value_of(new_lines[find_key(new_lines, "jwtKey")[0]], "jwtKey")
    if pw in text or jwt in text or len(pw) != 16 or len(jwt) != 44:
        stop("STOP-self-test-leaked")
    if "ADMIN-PASSWORD-LEN 16" not in text or "JWTKEY-LEN 44" not in text:
        stop("STOP-self-test-len-line")
    if "ADMIN-USER standalone" not in text.splitlines():
        stop("STOP-self-test-user")
    if (os.stat(str(cfg)).st_mode & 0o777) != 0o600:
        stop("STOP-self-test-mode")
    backups = matching_backups(tmp)
    if len(backups) != 1 or backups[0].read_text(encoding="utf-8") != body:
        stop("STOP-self-test-backup")
    pointer = read_pointer(tmp)
    if pointer != backups[0]:
        stop("STOP-self-test-pointer")

    code, text = capture(lambda: restore(cfg, False))
    if code != 0 or cfg.read_text(encoding="utf-8") != body or "CANARY" in text:
        stop("STOP-self-test-restore")

    bad = tmp / "bad.yml"
    bad.write_text(body + "  jwtKey: second-value-not-used-here\n", encoding="utf-8")
    before = bad.read_bytes()
    expect_stop(lambda: rotate(bad, False), "STOP-count-jwtKey")
    if bad.read_bytes() != before:
        stop("STOP-self-test-wrote")

    link_target = tmp / "real.yml"
    link_target.write_text(body, encoding="utf-8")
    link = tmp / "link.yml"
    link.symlink_to(link_target)
    expect_stop(lambda: rotate(link, False), "STOP-symlink")
    if link_target.read_text(encoding="utf-8") != body:
        stop("STOP-self-test-symlink-wrote")

    repo = tmp / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    git_cfg = repo / "config.yml"
    git_cfg.write_text(body, encoding="utf-8")
    expect_stop(lambda: rotate(git_cfg, False), "STOP-git")
    if git_cfg.read_text(encoding="utf-8") != body:
        stop("STOP-self-test-git-wrote")

    evil = tmp / "evil.yml"
    evil.write_text("nope\n", encoding="utf-8")
    (tmp / POINTER_NAME).write_text("../evil.yml\n", encoding="utf-8")
    expect_stop(lambda: restore(cfg, False), "STOP-pointer")
    if evil.read_text(encoding="utf-8") != "nope\n":
        stop("STOP-self-test-traversal")

    # Pointer was rejected in place; put back a valid one, rotate, then shred.
    (tmp / POINTER_NAME).unlink()
    code, _text = capture(lambda: rotate(cfg, False))
    if code != 0:
        stop("STOP-self-test-rerotate")
    kept = cfg.read_bytes()
    code, text = capture(lambda: shred(cfg, False))
    if code != 0 or not text.startswith("SHRED-OK "):
        stop("STOP-self-test-shred")
    if cfg.read_bytes() != kept or matching_backups(tmp) or (tmp / POINTER_NAME).exists():
        stop("STOP-self-test-shred-left")

    shutil.rmtree(tmp)
    print("SELF-TEST-OK")


def main():
    umask_private()
    mode = os.environ.get("STEP6_MODE", "")
    if mode == "self-test":
        self_test()
        return
    raw = os.environ.get("STEP6_CONFIG", "")
    cfg = Path(raw)
    if not cfg.is_absolute():
        stop("STOP-path")
    if mode == "rotate":
        rotate(cfg, True)
    elif mode == "restore":
        restore(cfg, True)
    elif mode == "shred":
        shred(cfg, True)
    else:
        stop("STOP-usage")


if __name__ == "__main__":
    main()
PY
