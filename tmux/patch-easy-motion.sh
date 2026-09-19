#!/usr/bin/env bash
set -euo pipefail

plugin_dir=${1:?usage: patch-easy-motion.sh PLUGIN_DIR}
renderer="$plugin_dir/scripts/easy_motion.py"
motion_script="$plugin_dir/scripts/easy_motion.sh"
marker='# dotfiles-smart-actions-render-v9'
cancel_marker='# dotfiles-easy-motion-cancel-v2'

[[ -f "$renderer" ]] || { echo "EasyMotion renderer not found: $renderer" >&2; exit 1; }
[[ -f "$motion_script" ]] || { echo "EasyMotion motion script not found: $motion_script" >&2; exit 1; }
python3 - "$motion_script" "$renderer" "$cancel_marker" <<'PY'
import pathlib
import sys

motion_path = pathlib.Path(sys.argv[1])
renderer_path = pathlib.Path(sys.argv[2])
marker = sys.argv[3]
motion_source = motion_path.read_text()
renderer_source = renderer_path.read_text()

if marker not in motion_source:
    old = """        read -r jump_command && \\
        [[ "$(awk '{ print $1 }' <<< "${jump_command}")" == "jump" ]] || return
"""
    new = """        # dotfiles-easy-motion-cancel-v2
        read -r jump_command && \\
        if [[ "$(awk '{ print $1 }' <<< "${jump_command}")" == "cancel" ]]; then
            tmux send-keys -t "${EASY_MOTION_ORIGINAL_PANE_ID}" -X cancel
            return 0
        fi
        [[ "$(awk '{ print $1 }' <<< "${jump_command}")" == "jump" ]] || return
"""
    if old not in motion_source:
        if '== "cancel"' not in motion_source:
            raise SystemExit("EasyMotion cancellation receive point not found")
        motion_source = motion_source.replace(
            "            return 0\n        fi",
            "            tmux send-keys -t \"${EASY_MOTION_ORIGINAL_PANE_ID}\" -X cancel\n            return 0\n        fi",
            1,
        )
        motion_source = motion_source.replace("# dotfiles-easy-motion-cancel-v1", marker, 1)
    motion_path.write_text(motion_source.replace(old, new, 1))

if marker not in renderer_source:
    old = """                if next_key == "esc":
                    break
"""
    new = """                # dotfiles-easy-motion-cancel-v1
                if next_key == "esc":
                    print("cancel", file=command_pipe)
                    command_pipe.flush()
                    break
"""
    if old not in renderer_source:
        if 'print("cancel", file=command_pipe)' not in renderer_source:
            raise SystemExit("EasyMotion cancellation send point not found")
        renderer_source = renderer_source.replace("                if next_key == \"esc\":", "                " + marker + "\n                if next_key == \"esc\":", 1)
    renderer_path.write_text(renderer_source.replace(old, new, 1))
PY
if grep -q "$marker" "$renderer" && grep -Fq '_smart_action_disabled_styles' "$renderer" && grep -Fq 'action_background_style_code.get' "$renderer" && grep -Fq 'text_pos, smart_action_background_styles, smart_action_ranges' "$renderer" && grep -Fq 'dim_style_code, smart_action_disabled_styles, smart_action_background_styles, smart_action_ranges' "$renderer" && grep -Fq 'target_type_to_color[target_type] + (_action_style_at' "$renderer" && ! grep -Fq '_smart_action_background_style()' "$renderer"; then
  exit 0
fi
grep -q '^def print_text_with_targets(' "$renderer" || {
  echo "Unsupported tmux-easy-motion renderer version" >&2
  exit 1
}

python3 - "$renderer" "$marker" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
marker = sys.argv[2]
source = path.read_text()

source = source.replace(
    "import io\nimport re\nimport subprocess\nimport sys\nimport termios\nimport time\n",
    "import io\nimport json\nimport re\nimport subprocess\nimport sys\nimport termios\nimport time\nimport unicodedata\n",
    1,
)

helpers = f'''{marker}
def _smart_action_detector():
    config = subprocess.check_output(
        ["tmux", "show-options", "-gqv", "@smart-actions-detector"],
        universal_newlines=True,
    ).strip()
    if config:
        return config.replace("~", __import__("os").path.expanduser("~"), 1)
    return __import__("os").path.expanduser(
        __import__("os").environ.get("XDG_CONFIG_HOME", "~/.config")
        + "/tmux/smart-actions.py"
    )


def _smart_action_ranges(capture_buffer):
    try:
        output = subprocess.check_output(
            ["python3", _smart_action_detector(), "--action-spans"],
            input=capture_buffer,
            universal_newlines=True,
            stderr=subprocess.DEVNULL,
        )
        return json.loads(output)
    except (OSError, ValueError, subprocess.CalledProcessError):
        return []


def _smart_action_style():
    try:
        style = subprocess.check_output(
            ["tmux", "show-options", "-gqv", "@smart-actions-highlight-style"],
            universal_newlines=True,
        ).strip()
        return TerminalCodes.Style.parse_style(style) if style else ""
    except (OSError, KeyError, IndexError, subprocess.CalledProcessError):
        return ""


def _smart_action_background_styles():
    def option(name):
        try:
            return subprocess.check_output(
                ["tmux", "show-options", "-gqv", name],
                universal_newlines=True,
            ).strip()
        except (OSError, subprocess.CalledProcessError):
            return ""

    try:
        style = option("@smart-actions-highlight-style")
        background = next(
            (part.split("=", 1)[1] for part in re.split(r"(?:\\s+)|(?:\\s*,\\s*)", style)
             if part.lower().startswith("bg=")),
            "",
        )
        default = TerminalCodes.Style.parse_style("bg=" + background) if background else ""
        styles = {{"default": default}}
        for action in ("open", "edit", "copy"):
            override = option("@smart-actions-" + action + "-background-style")
            styles[action] = TerminalCodes.Style.parse_style(override) if override else default
        return styles
    except (OSError, KeyError, IndexError, subprocess.CalledProcessError):
        return {{"default": ""}}


def _hex_rgb(value):
    match = re.fullmatch(r"#([0-9a-fA-F]{{3}}|[0-9a-fA-F]{{6}})", value.strip())
    if not match:
        return None
    digits = match.group(1)
    if len(digits) == 3:
        digits = "".join(char * 2 for char in digits)
    return tuple(int(digits[index:index + 2], 16) for index in (0, 2, 4))


def _relative_luminance(rgb):
    channels = []
    for value in rgb:
        channel = value / 255
        channels.append(channel / 12.92 if channel <= 0.03928 else ((channel + 0.055) / 1.055) ** 2.4)
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def _contrast_ratio(first, second):
    lighter = max(_relative_luminance(first), _relative_luminance(second))
    darker = min(_relative_luminance(first), _relative_luminance(second))
    return (lighter + 0.05) / (darker + 0.05)


def _smart_action_disabled_styles():
    def option(name):
        try:
            return subprocess.check_output(
                ["tmux", "show-options", "-gqv", name],
                universal_newlines=True,
            ).strip()
        except (OSError, subprocess.CalledProcessError):
            return ""

    highlight_style = option("@smart-actions-highlight-style")
    default_background = next(
        (part.split("=", 1)[1] for part in re.split(r"(?:\\s+)|(?:\\s*,\\s*)", highlight_style)
         if part.lower().startswith("bg=")),
        "",
    )
    styles = {{}}
    for action in ("open", "edit", "copy"):
        override = option("@smart-actions-" + action + "-background-style")
        background = next(
            (part.split("=", 1)[1] for part in re.split(r"(?:\\s+)|(?:\\s*,\\s*)", override)
             if part.lower().startswith("bg=")),
            default_background,
        )
        rgb = _hex_rgb(background)
        if rgb is None:
            styles[action] = ""
            continue
        light = (248, 250, 252)
        dark = (0, 0, 0)
        foreground = light if _contrast_ratio(rgb, light) >= _contrast_ratio(rgb, dark) else dark
        styles[action] = TerminalCodes.Style.parse_style(
            "none,fg=#%02x%02x%02x" % foreground
        )
    styles["default"] = styles.get("open", "")
    return styles


def _cell_width(char):
    if unicodedata.combining(char):
        return 0
    return 2 if unicodedata.east_asian_width(char) in "WFA" else 1


def _styled_capture_slice(text, start, end, dim_style_code, action_disabled_style_code, action_background_style_code, ranges):
    if not action_disabled_style_code and not action_background_style_code:
        return dim_style_code + text[start:end] + TerminalCodes.Style.RESET
    line = text.count("\\n", 0, start)
    line_start = text.rfind("\\n", 0, start) + 1
    column = sum(_cell_width(char) for char in text[line_start:start])
    parts = []
    active = None
    for char in text[start:end]:
        width = _cell_width(char)
        action = next(
            (item.get("action", "default") for item in ranges
             if item["row"] == line
             and column <= item["end_column"]
             and column + max(width, 1) - 1 >= item["start_column"]),
            None,
        )
        disabled_style = action_disabled_style_code.get(
            action, action_disabled_style_code.get("default", "")
        ) if action else ""
        background_style = action_background_style_code.get(
            action, action_background_style_code.get("default", "")
        ) if action else ""
        style = (dim_style_code + disabled_style + background_style
                 if disabled_style else dim_style_code + background_style)
        if style != active:
            if active is not None:
                parts.append(TerminalCodes.Style.RESET)
            parts.append(style)
            active = style
        parts.append(char)
        if char == "\\n":
            line += 1
            column = 0
        else:
            column += width
    if active is not None:
        parts.append(TerminalCodes.Style.RESET)
    return "".join(parts)


def _action_style_at(text, position, action_styles, ranges):
    line = text.count("\\n", 0, position)
    line_start = text.rfind("\\n", 0, position) + 1
    column = sum(_cell_width(char) for char in text[line_start:position])
    for item in ranges:
        if (item["row"] == line
                and item["start_column"] <= column <= item["end_column"]):
            return action_styles.get(item.get("action", ""), action_styles.get("default", ""))
    return None


'''

source = re.sub(
    r"# dotfiles-smart-actions-render-v[1-9].*?(?=\ndef print_text\()",
    lambda _match: helpers,
    source,
    count=1,
    flags=re.S,
)
if marker not in source:
    source = source.replace("def print_text(capture_buffer):\n", helpers + "def print_text(capture_buffer):\n", 1)

function_match = re.search(
    r"def print_text_with_targets\(.*?(?=\ndef [a-zA-Z_]|" r"\Z)", source, flags=re.S
)
if not function_match:
    raise SystemExit("EasyMotion renderer function not found")
function = function_match.group(0)
function = re.sub(
    r"    smart_action_ranges = _smart_action_ranges\(capture_buffer\)\n"
    r"    smart_action_style = _smart_action_style\(\)\n"
    r"    smart_action_background_styles = _smart_action_background_styles\(\)\n",
    "",
    function,
    count=1,
)
function = re.sub(
    r"    smart_action_ranges = _smart_action_ranges\(capture_buffer\)\n"
    r"    smart_action_style = _smart_action_style\(\)\n"
    r"    smart_action_background_style = _smart_action_background_style\(\)\n",
    "",
    function,
    count=1,
)
anchor = "    # type: (str, Iterable[Any], str, str, str, str, str, int) -> None\n"
if anchor not in function:
    raise SystemExit("EasyMotion renderer signature changed")
function = function.replace(
    anchor,
    anchor +
    "    smart_action_ranges = _smart_action_ranges(capture_buffer)\n"
    "    smart_action_style = _smart_action_style()\n"
    "    smart_action_background_styles = _smart_action_background_styles()\n"
    "    smart_action_disabled_styles = _smart_action_disabled_styles()\n",
    1,
)
function = function.replace(
    "[target_type_to_color[target_type], target_key, TerminalCodes.Style.RESET]",
    "[target_type_to_color[target_type] + (_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges) or \"\"), target_key, TerminalCodes.Style.RESET]",
)
function = function.replace(
    "[(_action_style_at(capture_buffer, text_pos, smart_action_style, smart_action_ranges) or target_type_to_color[target_type]), target_key, TerminalCodes.Style.RESET]",
    "[target_type_to_color[target_type] + (_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges) or \"\"), target_key, TerminalCodes.Style.RESET]",
)
function = function.replace(
    "_action_style_at(capture_buffer, text_pos, smart_action_style, smart_action_ranges)",
    "_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges)",
)
function = function.replace(
    "[(_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges) or target_type_to_color[target_type]), target_key, TerminalCodes.Style.RESET]",
    "[target_type_to_color[target_type] + (_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges) or \"\"), target_key, TerminalCodes.Style.RESET]",
)
function = function.replace(
    "[dim_style_code, capture_buffer[previous_text_pos + 1 : text_pos], TerminalCodes.Style.RESET]",
    "[_styled_capture_slice(capture_buffer, previous_text_pos + 1, text_pos, dim_style_code, smart_action_disabled_styles, smart_action_background_styles, smart_action_ranges)]",
)
function = function.replace(
    "[dim_style_code, rest_of_capture_buffer, TerminalCodes.Style.RESET]",
    "[_styled_capture_slice(capture_buffer, previous_text_pos + 1, len(capture_buffer.rstrip()), dim_style_code, smart_action_disabled_styles, smart_action_background_styles, smart_action_ranges)]",
)
function = function.replace(
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, text_pos, dim_style_code, smart_action_style, smart_action_background_styles, smart_action_ranges)",
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, text_pos, dim_style_code, smart_action_disabled_styles, smart_action_background_styles, smart_action_ranges)",
)
function = function.replace(
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, len(capture_buffer.rstrip()), dim_style_code, smart_action_style, smart_action_background_styles, smart_action_ranges)",
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, len(capture_buffer.rstrip()), dim_style_code, smart_action_disabled_styles, smart_action_background_styles, smart_action_ranges)",
)
function = function.replace(
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, text_pos, dim_style_code, smart_action_background_styles, smart_action_ranges)",
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, text_pos, dim_style_code, smart_action_disabled_styles, smart_action_background_styles, smart_action_ranges)",
)
function = function.replace(
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, len(capture_buffer.rstrip()), dim_style_code, smart_action_background_styles, smart_action_ranges)",
    "_styled_capture_slice(capture_buffer, previous_text_pos + 1, len(capture_buffer.rstrip()), dim_style_code, smart_action_disabled_styles, smart_action_background_styles, smart_action_ranges)",
)
source = source[:function_match.start()] + function + source[function_match.end():]
source = source.replace(
    "[(_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges) or target_type_to_color[target_type]), target_key, TerminalCodes.Style.RESET]",
    "[target_type_to_color[target_type] + (_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges) or \"\"), target_key, TerminalCodes.Style.RESET]",
)
source = source.replace(
    "_action_style_at(capture_buffer, text_pos, smart_action_background_style, smart_action_ranges)",
    "_action_style_at(capture_buffer, text_pos, smart_action_background_styles, smart_action_ranges)",
)
path.write_text(source)
PY
