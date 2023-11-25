import https from 'https';
import os from 'os';
import fs from 'fs';
import vs from 'vs-version-info';
import humanoid from 'humanoid-js';
import core from '@actions/core';

import { spawnSync } from 'child_process';

const REGION = process.env.LOL_REGION;
const IS_WINDOWS = os.platform() == 'win32';

console.log('REGION: ' + REGION);
console.log('IS_WINDOWS: ' + IS_WINDOWS);

let MANIFEST_DOWNLOADER_URL;
let MANIFEST_DOWNLOADER_PATH;
if (IS_WINDOWS) {
    MANIFEST_DOWNLOADER_URL = 'https://github.com/Morilli/ManifestDownloader/releases/download/v1.8.1/ManifestDownloader.exe';
    MANIFEST_DOWNLOADER_PATH = 'temp/ManifestDownloader.exe';
} else {
    MANIFEST_DOWNLOADER_URL = 'https://github.com/Morilli/ManifestDownloader/releases/download/v1.8.1/ManifestDownloader';
    MANIFEST_DOWNLOADER_PATH = 'temp/ManifestDownloader';
}

if (!fs.existsSync('temp')) {
    fs.mkdirSync('temp');
}

function fetch_async(url) {
    return new Promise(async (resolve, reject) => {
        let hmnd = new humanoid();
        hmnd.get(url)
            .then(res => {
                try {
                    return resolve(JSON.parse(res.body));
                } catch {
                    console.error('failed to fetch a resource!');
                    console.error(res.body);
                    return reject()
                }
            })
            .catch(err => {
                console.error('humanoid error');
                console.error(err)
                return reject(err)
            })
    });
}

function downloadToFile(url, path) {
	return new Promise((resolve, reject) => {
		https.get(url, response => {
			// redirection
			if (response.statusCode > 300 && response.statusCode < 400 && !!response.headers.location) {
				return resolve(downloadToFile(response.headers.location, path));
			}

			if (response.statusCode != 200) {
				return reject(new Error(response.statusMessage));
			}

			const stream = fs.createWriteStream(path).on('finish', () => {
				resolve({});
			})

			response.pipe(stream);
		}).on('error', error => {
			reject(error);
		});
	});
}

async function getGameVersion(region) {
    const content = await fetch_async(`https://sieve.services.riotcdn.net/api/v1/products/lol/version-sets/${region.toUpperCase()}?q[platform]=windows&q[published]=true`);
    return content["releases"][0]["compat_version"]["id"];
}

async function getClientVersion(region, patchline) {
	const UID = `${patchline}_${region}`;
    const MANIFEST_PATH = `temp/client_${UID}.manifest`;
	const OUT_PATH = `temp/${UID}`;
	const EXE_NAME = 'LeagueClient.exe';
    const CLIENT_PATH = `${OUT_PATH}/${EXE_NAME}`;

	if (!fs.existsSync(OUT_PATH)) {
		fs.mkdirSync(OUT_PATH);
	}

    const content = await fetch_async('https://clientconfig.rpg.riotgames.com/api/v1/config/public?namespace=keystone.products.league_of_legends.patchlines');

    function getPatchUrl() {
        const configs = content[`keystone.products.league_of_legends.patchlines.${patchline.toLowerCase()}`]['platforms']['win']['configurations'];

		if (configs.length == 1) {
			return configs[0]['patch_url'];
		}
        
        region = region.toUpperCase();
        for (const config of configs) {
            if (config['id'] == region) {
                return config['patch_url'];
            }
        }

		console.error(`could not find patch url for region ${patchline} in region ${region}!`);
		console.log('configs count: ' + configs.length);
        return undefined;
    }
    const patchUrl = getPatchUrl();
	console.log('patchUrl: ' + patchUrl);

    await downloadToFile(patchUrl, MANIFEST_PATH);

    spawnSync(MANIFEST_DOWNLOADER_PATH, [MANIFEST_PATH, '-f', EXE_NAME, '-o', OUT_PATH]);

    const buffer = fs.readFileSync(CLIENT_PATH);
    const versionInfo = vs.parseBytes(buffer)[0];
    const entry = versionInfo.getStringTables()[0];

    return entry['FileVersion'];
}

if (!fs.existsSync(MANIFEST_DOWNLOADER_PATH)) {
	await downloadToFile(MANIFEST_DOWNLOADER_URL, MANIFEST_DOWNLOADER_PATH);

	if (!IS_WINDOWS) {
		fs.chmodSync(MANIFEST_DOWNLOADER_PATH, 0o775);
	}
}

let configs = [
	{
		region: REGION,
		patchline: 'LIVE',
	},
	{
		region: 'PBE1',
		patchline: 'PBE',
	}
]

let versions = []
let tasks = [];
for (const cfg of configs) {
	versions[cfg.patchline] = {}

	tasks.push(
		getGameVersion(cfg.region).then((result) => {
			versions[cfg.patchline].game = result;
		}),
		getClientVersion(cfg.region, cfg.patchline).then((result) => {
			versions[cfg.patchline].client = result;
		})
	)
}

await Promise.all(tasks);
// console.log(versions)

for (const cfg of configs) {
	const patchline = cfg.patchline.toLowerCase();
	const currentVersion = versions[cfg.patchline];
	const lastVersion = JSON.parse(fs.readFileSync(`../../content/lol/${patchline}/version.txt`));

	// LCU prints version like 13.24.545.0457
	// But we get version like 13.24.545.457
	function fixClientVersion(text) {
		let v = text.split('.')
		v[3] = v[3].padStart(4, '0')
		return v.join('.')
	}

	const currentGameVersion = currentVersion.game;
	const currentClientVersion = fixClientVersion(currentVersion.client);
	const lastGameVersion  = lastVersion.game;
	const lastClientVersion = fixClientVersion(lastVersion.client);

	console.log('patchline:' + patchline);
	console.log('game version:');
	console.log('         old: ' + lastGameVersion);
	console.log('         new: ' + currentGameVersion);
	console.log('client version:');
	console.log('           old: ' + lastClientVersion);
	console.log('           new: ' + currentClientVersion);
	console.log('=========================================');

	let is_outdated = currentGameVersion != lastGameVersion || currentClientVersion != lastClientVersion;
	core.setOutput(`is_${patchline}_outdated`, is_outdated);
}
