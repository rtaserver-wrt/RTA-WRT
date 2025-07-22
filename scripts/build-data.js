// scripts/build-data.js
const fs = require('fs').promises; // Gunakan promise-based fs
const path = require('path');
const https = require('https'); // Modul https bawaan Node.js

const REPO_OWNER = 'rizkikotet-dev'; // Ganti dengan owner repo Anda
const REPO_NAME = 'RTA-WRT';       // Ganti dengan nama repo Anda
const GITHUB_TOKEN = process.env.REPO_PAT || process.env.GITHUB_TOKEN; // Ambil token dari environment variable
const OUTPUT_DIR = path.join(__dirname, '..', 'data'); // Output data (sesuaikan jika path HTML Anda berbeda)

// Fungsi helper untuk melakukan GET request ke GitHub API
async function fetchGitHubAPI(endpoint) {
    const options = {
        hostname: 'api.github.com',
        path: endpoint,
        method: 'GET',
        headers: {
            'User-Agent': 'RTA-WRT-Firmware-Site-Builder', // User agent yang baik
            'Accept': 'application/vnd.github.v3+json',
        }
    };

    if (GITHUB_TOKEN) {
        options.headers['Authorization'] = `token ${GITHUB_TOKEN}`;
    } else {
        console.warn('GITHUB_TOKEN not found. Making unauthenticated requests (lower rate limit).');
    }

    return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
            let data = '';
            console.log(`Workspaceing ${endpoint} - Status: ${res.statusCode}`);
            if (res.headers['x-ratelimit-remaining']) {
                console.log(`Rate limit remaining: ${res.headers['x-ratelimit-remaining']}`);
            }

            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', () => {
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        console.error("Failed to parse JSON response:", data);
                        reject(new Error(`Failed to parse JSON response for ${endpoint}: ${e.message}`));
                    }
                } else if (res.statusCode === 304) { // Not Modified
                     console.log(`Endpoint ${endpoint} not modified.`);
                     resolve(null); // Atau data lama jika Anda menggunakan ETag
                }else {
                    console.error(`Error fetching ${endpoint}: ${res.statusCode}`, data);
                    reject(new Error(`GitHub API request failed for ${endpoint} with status ${res.statusCode}. Response: ${data}`));
                }
            });
        });
        req.on('error', (error) => {
            reject(new Error(`Request error for ${endpoint}: ${error.message}`));
        });
        req.end();
    });
}

// Fungsi untuk mengambil dan memproses changelog dari file CHANGELOG.md
async function getChangelogContent() {
    try {
        const changelogData = await fetchGitHubAPI(`/repos/${REPO_OWNER}/${REPO_NAME}/contents/CHANGELOG.md`);
        if (changelogData && changelogData.content) {
            return Buffer.from(changelogData.content, 'base64').toString('utf-8');
        }
    } catch (error) {
        console.error('Could not fetch CHANGELOG.md:', error);
    }
    return null; // Kembalikan null jika gagal
}

async function buildStaticData() {
    try {
        await fs.mkdir(OUTPUT_DIR, { recursive: true }); // Buat direktori output jika belum ada

        // 1. Ambil rilis stabil terbaru
        console.log('Fetching latest stable release...');
        const stableRelease = await fetchGitHubAPI(`/repos/${REPO_OWNER}/${REPO_NAME}/releases/latest`);
        if (stableRelease) {
             await fs.writeFile(path.join(OUTPUT_DIR, 'stable_release.json'), JSON.stringify(stableRelease, null, 2));
             console.log('stable_release.json created.');
        } else {
             console.warn('No stable release found or API request failed.');
        }


        // 2. Ambil semua rilis (untuk pra-rilis)
        console.log('Fetching all releases (for pre-releases)...');
        const allReleases = await fetchGitHubAPI(`/repos/${REPO_OWNER}/${REPO_NAME}/releases`);
         if (allReleases && Array.isArray(allReleases)) {
             await fs.writeFile(path.join(OUTPUT_DIR, 'all_releases.json'), JSON.stringify(allReleases, null, 2));
             console.log('all_releases.json created.');
         } else {
             console.warn('No releases found or API request failed.');
         }

        // 3. (Opsional) Ambil konten CHANGELOG.md jika Anda membutuhkannya secara terpisah
        // Jika catatan rilis (release.body) sudah cukup, ini mungkin tidak perlu.
        console.log('Fetching CHANGELOG.md content...');
        const changelogMdContent = await getChangelogContent();
        if (changelogMdContent) {
            await fs.writeFile(path.join(OUTPUT_DIR, 'changelog_content.md'), changelogMdContent);
            console.log('changelog_content.md created.');
        }

        console.log('Static data build complete!');
    } catch (error) {
        console.error('Error during static data build:', error);
        process.exit(1); // Keluar dengan kode error jika build gagal
    }
}

buildStaticData();