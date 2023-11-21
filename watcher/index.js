import https from 'https';
import os from 'os';
import fs from 'fs';
import vs from 'vs-version-info';
import humanoid from 'humanoid-js';
import core from '@actions/core';

import { spawnSync } from 'child_process';

const REGION = process.env.LOL_REGION.toLowerCase();
const PATCHLINE = 'live';
const IS_WINDOWS = os.platform() == 'win32';

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

    // return new Promise(async (resolve, reject) => {
    //     for (let i = 0; i < 5; ++i) {
    //         const response = await fetch('https://api.allorigins.win/raw?url=' + encodeURIComponent(url));
    //         const content = await response.text();

    //         try {
    //             return resolve(JSON.parse(content));
    //         } catch {
    //             console.log(`failed to fetch a resource! retries left: ${5 - i - 1}`);
    //             console.log(content);
    //             await new Promise(r => setTimeout(r, 3000));
    //         }
    //     }
    
    //     reject();
    // });
}

async function getGameVersion() {
    const content = await fetch_async('https://sieve.services.riotcdn.net/api/v1/products/lol/version-sets/EUW1?q[platform]=windows&q[published]=true');
    return content["releases"][0]["compat_version"]["id"];
}

async function getClientVersion() {
    const MANIFEST_PATH = 'temp/client.manifest';
    const CLIENT_PATH = 'LeagueClient.exe'

    const content = await fetch_async('https://clientconfig.rpg.riotgames.com/api/v1/config/public?namespace=keystone.products.league_of_legends.patchlines');

    function getPatchUrl() {
        const configs = content[`keystone.products.league_of_legends.patchlines.${PATCHLINE.toLowerCase()}`]['platforms']['win']['configurations'];
        const region = REGION.toUpperCase();
        
        for (const config of configs) {
            if (config['id'] == region) {
                return config['patch_url'];
            }
        }

        return undefined;
    }
    const patchUrl = getPatchUrl();

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
    await downloadToFile(patchUrl, MANIFEST_PATH);

    await downloadToFile(MANIFEST_DOWNLOADER_URL, MANIFEST_DOWNLOADER_PATH);
    if (!IS_WINDOWS) {
        fs.chmodSync(MANIFEST_DOWNLOADER_PATH, 0o775);
    }

    spawnSync(MANIFEST_DOWNLOADER_PATH, [MANIFEST_PATH, '-f', CLIENT_PATH, '-o', 'temp']);

    const buffer = fs.readFileSync('temp/' + CLIENT_PATH);
    const versionInfo = vs.parseBytes(buffer)[0];
    const entry = versionInfo.getStringTables()[0];

    return entry['FileVersion'];
}

const currentGameVersion = await getGameVersion();
const currentClientVersion = await getClientVersion();

const version = JSON.parse(fs.readFileSync('../../content/lol/version.txt'));
const lastGameVersion  = version.game;
const lastClientVersion = version.client;

console.log('game version:  ');
console.log('         old:  ' + lastGameVersion);
console.log('         new:  ' + currentGameVersion);
console.log('client version:');
console.log('          old: ' + lastClientVersion);
console.log('          new: ' + currentClientVersion);

let is_outdated = currentGameVersion != lastGameVersion || currentClientVersion != lastClientVersion;
core.setOutput('is_outdated', is_outdated);
