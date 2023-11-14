export async function init(context: PenguContext) {
	context.rcp.preInit('rcp-fe-common-libs', async (provider) => {
		(window as any).__RCP_COMMON_PROVIDER = provider

		// Make sure 'output' folder exists
		await PluginFS.mkdir('output/')

		let plugins = await (await fetch('/plugin-manager/v2/plugins')).json()
		// console.log(plugins)

		let promises: Promise<any>[] = []

		for (let plugin of plugins) {
			let name = <string>plugin.fullName
			if (!name.startsWith('rcp-fe-')) {
				continue
			}

			promises.push(new Promise<any>((resolve, reject) => {
				let shortName = name.replace(/^rcp-fe-/, '')

				console.log(`Dumping ${shortName}...`)
				fetch(`/fe/${shortName}/${name}.js`).then(response => {
					if (!response.ok) {
						console.error(`Error fetching ${shortName}!`)
						console.error(`${response.status}: ${response.statusText}`)
						reject(null)
						return
					}

					response.text().then(text => {
						console.log(`Saving ${shortName}...`)

						PluginFS.write(`output/${shortName}.js`, text, false).then(status => {
							if (status != true) {
								console.error(`Error saving ${shortName}!`)
								reject(null)
								return
							}

							console.log(`Successfully dumped and saved ${shortName}!`)
							resolve(null)
						})
					})
				})
			}))
		}

		Promise.allSettled(promises).then(() => {
			// ................................
			// no comment
			PluginFS.write('status', '1', false)
		})
	})
}
