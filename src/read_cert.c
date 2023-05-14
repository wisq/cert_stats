#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <libgen.h>
#include <string.h>

/*
 * Paths to LetsEncrypt.
 *
 * If you use a non-standard install location, you can change these.
 *
 * Make sure to keep the trailing slash!
 */
#define LE_LIVE "/etc/letsencrypt/live/"

#ifdef __APPLE__
/* On MacOS, /etc is a symlink to /private/etc. */
#define LE_ARCHIVE "/private/etc/letsencrypt/archive/"
#else
#define LE_ARCHIVE "/etc/letsencrypt/archive/"
#endif

int read_cert(const char *path);
int is_archive_cert(char *base);

int main(int argc, char *argv[]) {
	if (argc == 2) {
		read_cert(argv[1]);
	} else {
		fprintf(stderr, "Usage: %s /path/to/cert.pem\n", argv[0]);
		return -1;
	}
}

int read_cert(const char *path) {
	if (strncmp(LE_LIVE, path, strlen(LE_LIVE)) != 0) {
		fprintf(stderr, "Path must start with \"%s\": %s\n", LE_LIVE, path);
		return -1;
	} else if (strcmp("cert.pem", basename((char *)path)) != 0) {
		fprintf(stderr, "Path must end with \"/cert.pem\": %s\n", path);
		return -1;
	}

	char real[PATH_MAX];

	if (realpath(path, real) == NULL) {
		perror("realpath");
		fprintf(stderr, "Must be run as a user that can read %s and %s.", LE_LIVE, LE_ARCHIVE);
		return -1;
	} else if (strncmp(LE_ARCHIVE, real, strlen(LE_ARCHIVE)) != 0) {
		fprintf(stderr, "Resolved path must start with \"%s\": %s\n", LE_ARCHIVE, real);
		return -1;
	} else if (!is_archive_cert(basename(real))) {
		fprintf(stderr, "Resolved path must end with \"/cert##.pem\": %s\n", real);
		return -1;
	}

	FILE *fd = fopen(real, "r");

	if (fd == NULL) {
		perror("fopen");
		return -1;
	}

	char buf[BUFSIZ];
	size_t bytes;

	while ((bytes = fread(&buf, sizeof(char), BUFSIZ, fd)) > 0) {
		fwrite(buf, sizeof(char), bytes, stdout);
	}

	fclose(fd);
	return 0;
}

int is_archive_cert(char *base) {
	char *ptr = base;

	if (strncmp("cert", ptr, 4) != 0) {
		return 0;
	}

	ptr += 4;
	while (*ptr >= '0' && *ptr <= '9') {
		ptr++;
	}

	if (strcmp(".pem", ptr) != 0) {
		return 0;
	}

	return 1;
}
