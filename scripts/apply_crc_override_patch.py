#!/usr/bin/env python3
from pathlib import Path
import sys


INSERT_AFTER = "static struct symbol *visited_symbols;\n"

CRC_CODE = r'''
struct crc_override {
	char name[256];
	unsigned long crc;
	struct crc_override *next;
};

static struct crc_override *crc_overrides;

static int is_hex_crc(const char *s)
{
	return s && strlen(s) > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X');
}

static void add_crc_override(const char *name, unsigned long crc)
{
	struct crc_override *entry;

	entry = malloc(sizeof(*entry));
	if (!entry)
		return;
	snprintf(entry->name, sizeof(entry->name), "%s", name);
	entry->crc = crc;
	entry->next = crc_overrides;
	crc_overrides = entry;
}

static void read_crc_override_file(const char *path)
{
	FILE *f;
	char a[256], b[256];

	if (!path || !*path)
		return;
	f = fopen(path, "r");
	if (!f)
		return;
	while (fscanf(f, "%255s %255s", a, b) == 2) {
		if (is_hex_crc(a))
			add_crc_override(b, strtoul(a, NULL, 16));
		else if (is_hex_crc(b))
			add_crc_override(a, strtoul(b, NULL, 16));
	}
	fclose(f);
}

static void load_crc_overrides(void)
{
	const char *path = getenv("KBUILD_CRC_OVERRIDES");

	read_crc_override_file(path);
	read_crc_override_file(".meizu_crc_overrides.tsv");
	read_crc_override_file("common/.meizu_crc_overrides.tsv");
}

static int lookup_crc_override(const char *name, unsigned long *crc)
{
	struct crc_override *entry;

	for (entry = crc_overrides; entry; entry = entry->next) {
		if (strcmp(entry->name, name) == 0) {
			*crc = entry->crc;
			return 1;
		}
	}
	return 0;
}
'''


def patch_genksyms(common: Path) -> None:
    path = common / "scripts/genksyms/genksyms.c"
    text = path.read_text()
    if "lookup_crc_override" in text:
        return
    if INSERT_AFTER not in text:
        raise SystemExit(f"cannot find insertion point in {path}")
    text = text.replace(INSERT_AFTER, INSERT_AFTER + CRC_CODE + "\n", 1)
    text = text.replace(
        "\t\tcrc = expand_and_crc_sym(sym, 0xffffffff) ^ 0xffffffff;\n",
        "\t\tcrc = expand_and_crc_sym(sym, 0xffffffff) ^ 0xffffffff;\n"
        "\t\tlookup_crc_override(name, &crc);\n",
        1,
    )
    text = text.replace(
        "\tif (flag_reference) {\n",
        "\tload_crc_overrides();\n\n\tif (flag_reference) {\n",
        1,
    )
    path.write_text(text)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_crc_override_patch.py <common-dir>")
    patch_genksyms(Path(sys.argv[1]))


if __name__ == "__main__":
    main()

