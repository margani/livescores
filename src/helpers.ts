import fs from 'fs';
import nunjucks from 'nunjucks';
import puppeteer from 'puppeteer';
import { Jimp } from 'jimp';

const LS_API_URL = 'https://prod-cdn-public-api.livescore.com/v1/api'
const LS_TEAM_API_URL = 'https://prod-cdn-team-api.livescore.com/v1/api/app/team'
const DATA_FILEPATH = 'src/data.json';
const GEN_FOLDER_NAME = 'generated'


function getData(): any {
    return JSON.parse(fs.readFileSync(DATA_FILEPATH, 'utf8'))
}
function saveData(data: any): any {
    fs.writeFileSync(DATA_FILEPATH, JSON.stringify(data, null, 2), 'utf8')
}
function getLeagueById(id: string) {
    return getData().leagues.find((league: any) => league.Id === id)
}
async function getTeamById(id: string) {
    const data = getData()
    let team = data.teams.find((team: any) => team.Id === id)
    if (!team) {
        team = await addTeam(id)
    }

    return team
}
async function addTeam(id: string) {
    const url = `${LS_TEAM_API_URL}/${id}/details`
    const teamData = await (await fetch(url)).json()
    const team = {
        Id: teamData.ID,
        Name: teamData.Nm,
        Abbreviation: teamData.Abr,
        LogoUrl: `https://lsm-static-prod.livescore.com/medium/${teamData.Img}`
    }

    const data = getData()
    data.teams.push(team)
    saveData(data)

    return team
}
async function getLeagueTable(league: any): Promise<any> {
    try {
        const url = `${LS_API_URL}/app/stage/soccer/${league.CountrySlug}/${league.Slug}/0`
        const data = await (await fetch(url)).json()
        if (!data.Stages[0].LeagueTable) {
            console.log(`No league table found for ${league.CountrySlug}/${league.Slug}`)
            return null
        }

        const table = data.Stages[0].LeagueTable.L[0].Tables.find((table: any) => table.LTT === 1)
        const stanings = [];
        for (const standing of table.team) {
            const team = await getTeamById(standing.Tid)
            stanings.push({
                position: standing.rnk,
                played: standing.pld,
                wins: standing.win,
                draws: standing.drw,
                losses: standing.lst,
                goalDifference: standing.gd,
                goalAgainst: standing.ga,
                goalFor: standing.gf,
                points: standing.pts,
                team,
            })
        }

        return stanings.sort((a: any, b: any) => a.position - b.position)
    } catch (error) {
        console.log('ERROR!')
        console.error(error)
        return null
    }
}

export async function renderLeaguesTables() {
    const leagues = getData().leagues
    for (const league of leagues) {
        await renderLeagueTable(league.Id)
    }
}

async function renderLeagueTable(leagueId: string) {
    const league = getLeagueById(leagueId)
    if (!league) {
        console.error(`League with id ${leagueId} not found`)
        return
    }

    const standings = await getLeagueTable(league)
    if (!standings) {
        return
    }

    const templateContent = fs.readFileSync('src/templates/template.html', 'utf8');
    const htmlString = nunjucks.renderString(templateContent, {
        league,
        standings,
        matchWeek: standings.reduce((max: number, standing: any) => Math.max(max, standing.played), 0),
        season: '2024/25'
    });

    const folderName = GEN_FOLDER_NAME
    if (!fs.existsSync(folderName)) {
        fs.mkdirSync(folderName);
    }

    const generatedImageFilePath: `${string}.${string}` = `${folderName}/table-${leagueId}.png`
    await renderHtmlToImage(htmlString, generatedImageFilePath)
        .then(() => console.log('Image saved as output.png'))
        .catch(console.error);
    await trimImage(generatedImageFilePath)
    await addMarginToImage(generatedImageFilePath, 20)
}

async function renderHtmlToImage(htmlString: string, imageFilePath: string) {
    const browser = await puppeteer.launch();
    const page = await browser.newPage();
    await page.setContent(htmlString, { waitUntil: 'load' });
    await page.screenshot({ path: imageFilePath, fullPage: true });
    await browser.close();
}

async function trimImage(imageFilePath: `${string}.${string}`) {
    const image = await Jimp.read(imageFilePath)
    image.autocrop()
    await image.write(imageFilePath);
}

async function addMarginToImage(imageFilePath: `${string}.${string}`, marginSize: number) {
    const image = await Jimp.read(imageFilePath)
    const widthWithMargin = image.width + marginSize * 2;
    const heightWithMargin = image.height + marginSize * 2;
    const background = new Jimp({
        height: heightWithMargin,
        width: widthWithMargin,
        color: '#FFFFFF'
    });
    background.composite(image, marginSize, marginSize);
    await background.write(imageFilePath);
}
