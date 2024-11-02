import { ArgumentParser } from 'argparse';
import { renderLeaguesTables } from './helpers.js';

interface Actions {
    [key: string]: () => Promise<void>;
}

const parser = new ArgumentParser();

parser.add_argument('-a', '--action', { help: 'Specify the action to perform', required: true });
const args = parser.parse_args();
const action = args.action;

const actions: Actions = {
    "generate-league-table": async () => {
        await renderLeaguesTables();
    },
};

if (!action || !actions[action]) {
    console.log(`Unknown action: [${action}], pass --action=<action>`);
    process.exit(1);
}

(async () => {
    console.log(`[${action}] Executing action`);
    await actions[action]();
    console.log(`[${action}] Action completed`);
})();
