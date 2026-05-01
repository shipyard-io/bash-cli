package cli

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

var (
	repoPattern  = regexp.MustCompile(`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`)
	namePattern  = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)
	portPattern  = regexp.MustCompile(`^[0-9]{1,5}$`)
	healthRegexp = regexp.MustCompile(`^/.*`)
)

type prompt struct {
	in  *bufio.Reader
	out io.Writer
}

type CommonOptions struct {
	Repo           string
	NonInteractive bool
}

type SetupOptions struct {
	CommonOptions
	EnvFile string
}

type SecretsOptions struct {
	CommonOptions
	SecretName string
	Value      string
	ValueFile  string
}

func newPrompt() *prompt {
	return &prompt{in: bufio.NewReader(os.Stdin), out: os.Stderr}
}

func (p *prompt) ask(label, def string) (string, error) {
	if def != "" {
		fmt.Fprintf(p.out, "%s (%s): ", label, def)
	} else {
		fmt.Fprintf(p.out, "%s: ", label)
	}
	line, err := p.in.ReadString('\n')
	if err != nil && err != io.EOF {
		return "", err
	}
	value := strings.TrimSpace(line)
	if value == "" {
		return def, nil
	}
	return value, nil
}

func (p *prompt) askRequired(label, def string) (string, error) {
	for {
		v, err := p.ask(label, def)
		if err != nil {
			return "", err
		}
		if strings.TrimSpace(v) != "" {
			return v, nil
		}
		fmt.Fprintln(p.out, "Không được để trống")
	}
}

func (p *prompt) askSecret(label string) (string, error) {
	fmt.Fprintf(p.out, "%s: ", label)
	_ = exec.Command("stty", "-echo").Run()
	defer exec.Command("stty", "echo").Run()
	line, err := p.in.ReadString('\n')
	fmt.Fprintln(p.out)
	if err != nil && err != io.EOF {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

func (p *prompt) askChoice(label string, options []string) (string, error) {
	fmt.Fprintf(p.out, "%s\n", label)
	for i, opt := range options {
		fmt.Fprintf(p.out, "  %d) %s\n", i+1, opt)
	}
	for {
		v, err := p.ask("Chọn", "1")
		if err != nil {
			return "", err
		}
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > len(options) {
			fmt.Fprintln(p.out, "Lựa chọn không hợp lệ")
			continue
		}
		return options[n-1], nil
	}
}

func (p *prompt) readMultiline(title string) (string, error) {
	fmt.Fprintf(p.out, "%s\n", title)
	fmt.Fprintln(p.out, "Kết thúc bằng một dòng chỉ chứa: END")
	var lines []string
	for {
		line, err := p.in.ReadString('\n')
		if err != nil && err != io.EOF {
			return "", err
		}
		trimmed := strings.TrimRight(line, "\r\n")
		if trimmed == "END" {
			break
		}
		if err == io.EOF {
			if trimmed != "" {
				lines = append(lines, trimmed)
			}
			break
		}
		lines = append(lines, trimmed)
	}
	return strings.TrimRight(strings.Join(lines, "\n"), "\n"), nil
}

func runCommandInput(input []byte, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	if input != nil {
		cmd.Stdin = bytes.NewReader(input)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s %s failed: %w\n%s", name, strings.Join(args, " "), err, strings.TrimSpace(string(out)))
	}
	return strings.TrimSpace(string(out)), nil
}

func checkDependencies(names ...string) error {
	for _, n := range names {
		if _, err := exec.LookPath(n); err != nil {
			return fmt.Errorf("thiếu dependency: %s", n)
		}
	}
	return nil
}

func requireGHAuth() error {
	_, err := runCommandInput(nil, "gh", "auth", "status")
	if err != nil {
		return fmt.Errorf("chưa login GitHub CLI. Chạy: gh auth login")
	}
	return nil
}

func currentRepo(repoOverride string) (string, error) {
	if strings.TrimSpace(repoOverride) != "" {
		if !repoPattern.MatchString(repoOverride) {
			return "", fmt.Errorf("repo không hợp lệ: %s", repoOverride)
		}
		return repoOverride, nil
	}
	repo, err := runCommandInput(nil, "gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner")
	if err != nil {
		return "", err
	}
	if !repoPattern.MatchString(repo) {
		return "", fmt.Errorf("không tìm thấy repo GitHub hiện tại")
	}
	return repo, nil
}

func ghSecretSet(repo, name, value string) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	args := []string{}
	if strings.TrimSpace(repo) != "" {
		args = append(args, "-R", repo)
	}
	args = append(args, "secret", "set", name)
	_, err := runCommandInput([]byte(value), "gh", args...)
	return err
}

func ghSecretSetFromFile(repo, name, path string) error {
	args := []string{}
	if strings.TrimSpace(repo) != "" {
		args = append(args, "-R", repo)
	}
	args = append(args, "secret", "set", name)
	cmd := exec.Command("gh", args...)
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	cmd.Stdin = f
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("gh secret set %s failed: %w\n%s", name, err, string(out))
	}
	return nil
}

func validateIPOrHost(v string) error {
	if net.ParseIP(v) != nil {
		return nil
	}
	if strings.TrimSpace(v) == "" || strings.Contains(v, " ") {
		return fmt.Errorf("server ip/domain không hợp lệ")
	}
	return nil
}

func validateAppName(v string) error {
	if !namePattern.MatchString(v) {
		return fmt.Errorf("app name không hợp lệ, chỉ cho phép a-z A-Z 0-9 . _ -")
	}
	return nil
}

func validatePort(v string) error {
	if !portPattern.MatchString(v) {
		return fmt.Errorf("port không hợp lệ")
	}
	n, _ := strconv.Atoi(v)
	if n < 1 || n > 65535 {
		return fmt.Errorf("port ngoài range 1-65535")
	}
	return nil
}

func validateHealthPath(v string) error {
	if !healthRegexp.MatchString(v) {
		return fmt.Errorf("health path phải bắt đầu bằng /")
	}
	return nil
}

func testSSH(user, host, keyPath string) error {
	_, err := runCommandInput(nil, "ssh", "-n", "-i", keyPath, "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=accept-new", user+"@"+host, "exit")
	return err
}

func testTelegram(token, chatID, repo string) error {
	form := url.Values{}
	form.Set("chat_id", chatID)
	form.Set("text", "Shipyard CLI: Kết nối thành công! Repo: "+repo)
	resp, err := http.PostForm("https://api.telegram.org/bot"+token+"/sendMessage", form)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("telegram api status: %d", resp.StatusCode)
	}
	return nil
}

func resolveARecord(domain string) string {
	if strings.TrimSpace(domain) == "" {
		return ""
	}
	ips, err := net.LookupIP(domain)
	if err != nil || len(ips) == 0 {
		return ""
	}
	for _, ip := range ips {
		if v4 := ip.To4(); v4 != nil {
			return v4.String()
		}
	}
	return ips[0].String()
}

func readFileMaybe(path string) (string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return strings.TrimRight(string(b), "\n"), nil
}

func mergeEnv(base string, resolved map[string]string) string {
	lines := strings.Split(base, "\n")
	skip := map[string]bool{}
	for k := range resolved {
		skip[k] = true
	}
	var kept []string
	for _, line := range lines {
		trim := strings.TrimSpace(line)
		if trim == "" || strings.HasPrefix(trim, "#") || !strings.Contains(trim, "=") {
			if trim != "" {
				kept = append(kept, line)
			}
			continue
		}
		k := strings.SplitN(trim, "=", 2)[0]
		if !skip[k] {
			kept = append(kept, line)
		}
	}
	ordered := []string{"APP_NAME", "APP_PORT", "APP_DOMAIN", "DOMAIN", "HEALTH_CHECK_PATH", "INIT_INFRA"}
	var out []string
	for _, k := range ordered {
		if v, ok := resolved[k]; ok {
			out = append(out, k+"="+v)
		}
	}
	out = append(out, kept...)
	return strings.Join(out, "\n")
}

func parseEnvKV(base, key string) string {
	for _, line := range strings.Split(base, "\n") {
		if strings.HasPrefix(line, key+"=") {
			return strings.TrimPrefix(line, key+"=")
		}
	}
	return ""
}

func askValidated(p *prompt, label, def string, validate func(string) error) (string, error) {
	for {
		v, err := p.ask(label, def)
		if err != nil {
			return "", err
		}
		if err := validate(v); err != nil {
			fmt.Fprintln(p.out, err.Error())
			continue
		}
		return v, nil
	}
}

func RunSetup(opts SetupOptions) error {
	if err := checkDependencies("gh", "ssh"); err != nil {
		return err
	}
	if err := requireGHAuth(); err != nil {
		return err
	}
	repo, err := currentRepo(opts.Repo)
	if err != nil {
		return err
	}

	p := newPrompt()
	fmt.Fprintln(p.out, "--- Shipyard Zero-Touch Setup CLI ---")
	if opts.NonInteractive {
		return runSetupNonInteractive(repo, opts)
	}
	serverIP, err := askValidated(p, "Server IP", "", validateIPOrHost)
	if err != nil {
		return err
	}
	serverUser, err := askValidated(p, "SSH User", "root", func(s string) error {
		if !namePattern.MatchString(s) {
			return fmt.Errorf("ssh user không hợp lệ")
		}
		return nil
	})
	if err != nil {
		return err
	}
	defaultKey := filepath.Join(os.Getenv("HOME"), ".ssh", "id_rsa")
	sshKeyPath, err := p.askRequired("SSH Private Key", defaultKey)
	if err != nil {
		return err
	}
	if _, err := os.Stat(sshKeyPath); err != nil {
		return fmt.Errorf("không tìm thấy SSH key: %s", sshKeyPath)
	}
	if err := testSSH(serverUser, serverIP, sshKeyPath); err != nil {
		return fmt.Errorf("ssh fail: %w", err)
	}
	fmt.Fprintln(p.out, "SSH OK")

	tgToken, err := p.askSecret("Bot Token (optional)")
	if err != nil {
		return err
	}
	tgChatID, err := p.ask("Chat ID (optional)", "")
	if err != nil {
		return err
	}
	if tgToken != "" && tgChatID != "" {
		if err := testTelegram(tgToken, tgChatID, repo); err != nil {
			fmt.Fprintf(p.out, "Telegram test fail: %v\n", err)
		} else {
			fmt.Fprintln(p.out, "Telegram test OK")
		}
	}

	appName, err := askValidated(p, "App Name", "", validateAppName)
	if err != nil {
		return err
	}
	appDomain, err := p.ask("App Domain", "")
	if err != nil {
		return err
	}
	domain, err := p.ask("Root Domain", "")
	if err != nil {
		return err
	}
	appPort, err := askValidated(p, "Port", "80", validatePort)
	if err != nil {
		return err
	}
	healthPath, err := askValidated(p, "Health Path", "/", validateHealthPath)
	if err != nil {
		return err
	}

	for _, d := range []string{appDomain, domain} {
		if d == "" {
			continue
		}
		ip := resolveARecord(d)
		switch {
		case ip == "":
			fmt.Fprintf(p.out, "DNS FAIL: %s\n", d)
		case ip == serverIP:
			fmt.Fprintf(p.out, "DNS OK: %s -> %s\n", d, serverIP)
		default:
			fmt.Fprintf(p.out, "DNS WARNING: %s -> %s (expected %s)\n", d, ip, serverIP)
		}
	}

	mode, err := p.askChoice("Chọn mode ENV", []string{"Manual (KEY=VALUE)", "Paste .env"})
	if err != nil {
		return err
	}
	var customEnvs string
	if strings.Contains(mode, "Paste") {
		multiline, err := p.readMultiline("Nhập/paste .env")
		if err != nil {
			return err
		}
		customEnvs = multiline
	} else {
		for {
			entry, err := p.ask("ENV (empty to stop)", "")
			if err != nil {
				return err
			}
			if entry == "" {
				break
			}
			customEnvs += entry + "\n"
		}
	}

	envContent := strings.TrimSpace(strings.Join([]string{
		"APP_NAME=" + appName,
		"APP_PORT=" + appPort,
		"APP_DOMAIN=" + appDomain,
		"DOMAIN=" + domain,
		"HEALTH_CHECK_PATH=" + healthPath,
		"INIT_INFRA=true",
		customEnvs,
	}, "\n"))

	cfCert, err := p.ask("Cloudflare Origin Cert (optional)", "")
	if err != nil {
		return err
	}
	cfKey, err := p.ask("Cloudflare Origin Key (optional)", "")
	if err != nil {
		return err
	}
	traefikAuth, err := p.ask("Traefik Dashboard Auth (optional)", "")
	if err != nil {
		return err
	}

	fmt.Fprintln(p.out, "Đang set GitHub secrets...")
	if err := ghSecretSet(repo, "SERVER_IP", serverIP); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "SERVER_USER", serverUser); err != nil {
		return err
	}
	if err := ghSecretSetFromFile(repo, "SSH_PRIVATE_KEY", sshKeyPath); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "TELEGRAM_BOT_TOKEN", tgToken); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "TELEGRAM_CHAT_ID", tgChatID); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "CLOUDFLARE_ORIGIN_CERT", cfCert); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "CLOUDFLARE_ORIGIN_KEY", cfKey); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "TRAEFIK_DASHBOARD_AUTH", traefikAuth); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "ENV_FILE_CONTENT", envContent); err != nil {
		return err
	}

	fmt.Fprintf(p.out, "Done. Repo: %s | App: %s\n", repo, appName)
	return nil
}

func RunSecrets(opts SecretsOptions) error {
	if err := checkDependencies("gh"); err != nil {
		return err
	}
	if err := requireGHAuth(); err != nil {
		return err
	}
	repo, err := currentRepo(opts.Repo)
	if err != nil {
		return err
	}
	if opts.NonInteractive {
		return runSecretsNonInteractive(repo, opts)
	}
	p := newPrompt()
	fmt.Fprintf(p.out, "--- Shipyard Secret Manager (%s) ---\n", repo)

	secretList := []string{
		"SERVER_IP",
		"SERVER_USER",
		"SSH_PRIVATE_KEY",
		"TELEGRAM_BOT_TOKEN",
		"TELEGRAM_CHAT_ID",
		"CLOUDFLARE_ORIGIN_CERT",
		"CLOUDFLARE_ORIGIN_KEY",
		"TRAEFIK_DASHBOARD_AUTH",
		"ENV_FILE_CONTENT",
		"Tùy chỉnh (nhập tên secret)",
		"Thoát",
	}

	for {
		selected, err := p.askChoice("Secret cần set", secretList)
		if err != nil {
			return err
		}
		if selected == "Thoát" {
			break
		}

		secretName := selected
		if strings.HasPrefix(selected, "Tùy chỉnh") {
			v, err := p.askRequired("Nhập tên secret", "")
			if err != nil {
				return err
			}
			secretName = v
		}

		switch secretName {
		case "SSH_PRIVATE_KEY":
			path, err := p.askRequired("Đường dẫn file SSH Private Key", filepath.Join(os.Getenv("HOME"), ".ssh", "id_rsa"))
			if err != nil {
				return err
			}
			if _, err := os.Stat(path); err != nil {
				return err
			}
			if err := ghSecretSetFromFile(repo, secretName, path); err != nil {
				return err
			}
		case "TRAEFIK_DASHBOARD_AUTH":
			mode, err := p.askChoice("Chọn cách nhập Traefik Auth", []string{"Tự sinh từ Username + Password", "Nhập thủ công (htpasswd format)"})
			if err != nil {
				return err
			}
			value := ""
			if strings.Contains(mode, "Tự sinh") {
				u, err := p.askRequired("Username", "")
				if err != nil {
					return err
				}
				pw, err := p.askSecret("Password")
				if err != nil {
					return err
				}
				hash, err := runCommandInput(nil, "openssl", "passwd", "-apr1", pw)
				if err != nil {
					return err
				}
				value = u + ":" + hash
			} else {
				v, err := p.askRequired("Nhập htpasswd string (user:hash)", "")
				if err != nil {
					return err
				}
				value = v
			}
			if err := ghSecretSet(repo, secretName, value); err != nil {
				return err
			}
		case "CLOUDFLARE_ORIGIN_CERT", "CLOUDFLARE_ORIGIN_KEY":
			value, err := p.readMultiline("Paste certificate/key")
			if err != nil {
				return err
			}
			if err := ghSecretSet(repo, secretName, value); err != nil {
				return err
			}
		case "ENV_FILE_CONTENT":
			mode, err := p.askChoice("Nhập ENV như thế nào?", []string{"Paste trực tiếp", "Đọc từ file .env", "Cập nhật từ base .env file"})
			if err != nil {
				return err
			}

			base := ""
			if strings.Contains(mode, "Đọc từ file") || strings.Contains(mode, "Cập nhật") {
				path, err := p.askRequired("Đường dẫn file .env", ".env")
				if err != nil {
					return err
				}
				b, err := readFileMaybe(path)
				if err != nil {
					return err
				}
				base = b
			} else {
				v, err := p.readMultiline("Paste ENV")
				if err != nil {
					return err
				}
				base = strings.TrimRight(v, "\n")
			}

			appName, err := p.ask("APP_NAME", parseEnvKV(base, "APP_NAME"))
			if err != nil {
				return err
			}
			appPort, err := p.ask("APP_PORT", firstNonEmpty(parseEnvKV(base, "APP_PORT"), "80"))
			if err != nil {
				return err
			}
			appDomain, err := p.ask("APP_DOMAIN", parseEnvKV(base, "APP_DOMAIN"))
			if err != nil {
				return err
			}
			domain, err := p.ask("DOMAIN", parseEnvKV(base, "DOMAIN"))
			if err != nil {
				return err
			}
			health, err := p.ask("HEALTH_CHECK_PATH", firstNonEmpty(parseEnvKV(base, "HEALTH_CHECK_PATH"), "/"))
			if err != nil {
				return err
			}
			initInfra, err := p.ask("INIT_INFRA", firstNonEmpty(parseEnvKV(base, "INIT_INFRA"), "true"))
			if err != nil {
				return err
			}

			resolved := map[string]string{
				"APP_NAME":          appName,
				"APP_PORT":          appPort,
				"APP_DOMAIN":        appDomain,
				"DOMAIN":            domain,
				"HEALTH_CHECK_PATH": health,
				"INIT_INFRA":        initInfra,
			}
			value := mergeEnv(base, resolved)
			fmt.Fprintf(p.out, "Preview ENV_FILE_CONTENT:\n%s\n", value)
			if err := ghSecretSet(repo, secretName, value); err != nil {
				return err
			}
		case "TELEGRAM_BOT_TOKEN":
			v, err := p.askSecret(secretName)
			if err != nil {
				return err
			}
			if err := ghSecretSet(repo, secretName, v); err != nil {
				return err
			}
		default:
			v, err := p.askRequired(secretName, "")
			if err != nil {
				return err
			}
			if err := ghSecretSet(repo, secretName, v); err != nil {
				return err
			}
		}

		fmt.Fprintf(p.out, "✓ %s đã được cập nhật\n", secretName)
		time.Sleep(150 * time.Millisecond)
	}

	fmt.Fprintln(p.out, "Hoàn tất cập nhật secrets")
	return nil
}

func runSetupNonInteractive(repo string, opts SetupOptions) error {
	serverIP := strings.TrimSpace(os.Getenv("SHIPYARD_SERVER_IP"))
	serverUser := firstNonEmpty(strings.TrimSpace(os.Getenv("SHIPYARD_SERVER_USER")), "root")
	sshKeyPath := firstNonEmpty(strings.TrimSpace(os.Getenv("SHIPYARD_SSH_KEY_PATH")), filepath.Join(os.Getenv("HOME"), ".ssh", "id_rsa"))
	appName := strings.TrimSpace(os.Getenv("SHIPYARD_APP_NAME"))
	appPort := firstNonEmpty(strings.TrimSpace(os.Getenv("SHIPYARD_APP_PORT")), "80")
	healthPath := firstNonEmpty(strings.TrimSpace(os.Getenv("SHIPYARD_HEALTH_CHECK_PATH")), "/")
	appDomain := strings.TrimSpace(os.Getenv("SHIPYARD_APP_DOMAIN"))
	domain := strings.TrimSpace(os.Getenv("SHIPYARD_DOMAIN"))
	customEnvs := strings.TrimSpace(os.Getenv("SHIPYARD_CUSTOM_ENVS"))

	if serverIP == "" || appName == "" {
		return fmt.Errorf("non-interactive setup cần SHIPYARD_SERVER_IP và SHIPYARD_APP_NAME")
	}
	if err := validateIPOrHost(serverIP); err != nil {
		return err
	}
	if err := validateAppName(appName); err != nil {
		return err
	}
	if err := validatePort(appPort); err != nil {
		return err
	}
	if err := validateHealthPath(healthPath); err != nil {
		return err
	}
	if _, err := os.Stat(sshKeyPath); err != nil {
		return fmt.Errorf("không tìm thấy SSH key: %s", sshKeyPath)
	}

	if err := testSSH(serverUser, serverIP, sshKeyPath); err != nil {
		return fmt.Errorf("ssh fail: %w", err)
	}

	baseEnv := ""
	if strings.TrimSpace(opts.EnvFile) != "" {
		b, err := readFileMaybe(opts.EnvFile)
		if err != nil {
			return err
		}
		baseEnv = b
	}
	resolved := map[string]string{
		"APP_NAME":          appName,
		"APP_PORT":          appPort,
		"APP_DOMAIN":        appDomain,
		"DOMAIN":            domain,
		"HEALTH_CHECK_PATH": healthPath,
		"INIT_INFRA":        "true",
	}
	envContent := mergeEnv(baseEnv, resolved)
	if customEnvs != "" {
		envContent = strings.TrimSpace(envContent + "\n" + customEnvs)
	}

	if err := ghSecretSet(repo, "SERVER_IP", serverIP); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "SERVER_USER", serverUser); err != nil {
		return err
	}
	if err := ghSecretSetFromFile(repo, "SSH_PRIVATE_KEY", sshKeyPath); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "TELEGRAM_BOT_TOKEN", strings.TrimSpace(os.Getenv("SHIPYARD_TELEGRAM_BOT_TOKEN"))); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "TELEGRAM_CHAT_ID", strings.TrimSpace(os.Getenv("SHIPYARD_TELEGRAM_CHAT_ID"))); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "CLOUDFLARE_ORIGIN_CERT", os.Getenv("SHIPYARD_CLOUDFLARE_ORIGIN_CERT")); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "CLOUDFLARE_ORIGIN_KEY", os.Getenv("SHIPYARD_CLOUDFLARE_ORIGIN_KEY")); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "TRAEFIK_DASHBOARD_AUTH", strings.TrimSpace(os.Getenv("SHIPYARD_TRAEFIK_DASHBOARD_AUTH"))); err != nil {
		return err
	}
	if err := ghSecretSet(repo, "ENV_FILE_CONTENT", envContent); err != nil {
		return err
	}
	return nil
}

func runSecretsNonInteractive(repo string, opts SecretsOptions) error {
	secretName := strings.TrimSpace(opts.SecretName)
	if secretName == "" {
		secretName = strings.TrimSpace(os.Getenv("SHIPYARD_SECRET_NAME"))
	}
	if secretName == "" {
		return fmt.Errorf("non-interactive secrets cần --secret hoặc SHIPYARD_SECRET_NAME")
	}

	var value string
	if strings.TrimSpace(opts.ValueFile) != "" {
		b, err := os.ReadFile(opts.ValueFile)
		if err != nil {
			return err
		}
		value = strings.TrimRight(string(b), "\n")
	} else if strings.TrimSpace(opts.Value) != "" {
		value = opts.Value
	} else {
		value = os.Getenv("SHIPYARD_SECRET_VALUE")
	}

	if strings.TrimSpace(value) == "" {
		return fmt.Errorf("non-interactive secrets cần --value/--value-file hoặc SHIPYARD_SECRET_VALUE")
	}
	return ghSecretSet(repo, secretName, value)
}

func firstNonEmpty(v, fallback string) string {
	if strings.TrimSpace(v) == "" {
		return fallback
	}
	return v
}
