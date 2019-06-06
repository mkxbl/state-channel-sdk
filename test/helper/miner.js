const Migrations = artifacts.require('Migrations');

async function mine(n) {
    while(n-- > 0) {
        await Migrations.new();
    }
}

module.exports = {
    mine,
}