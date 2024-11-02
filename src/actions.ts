import { ArgumentParser } from 'argparse';

interface Actions {
    [key: string]: () => void;
}

const parser = new ArgumentParser();

parser.add_argument('-a', '--action', { help: 'Specify the action to perform', required: true });
const args = parser.parse_args();
const action = args.action;

const actions: Actions = {
    "sample-action": () => {
        console.log("doing action");
    },
};

if (!action || !actions[action]) {
    console.log(`Unknown action: ${action}, pass --action=<action>`);
    process.exit(1);
}

console.log(`[${action}] Executing action`);
actions[action]();
console.log(`[${action}] Action completed`);
