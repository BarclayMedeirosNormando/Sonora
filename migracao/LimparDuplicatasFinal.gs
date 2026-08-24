// ============================================================
// Limpeza final dos 114 pares duplicados restantes (os que a limpeza
// anterior não mexeu porque os dois lados estavam "Concluído").
//
// Critério usado (decidido em cima da contagem real de mp3 de cada lado,
// via VerificarDuplicatasRestantes.gs): mantém o lado com MAIS mp3
// (ou um dos dois, arbitrariamente, quando empatados ou quando os dois
// estão vazios) e joga o outro lado na lixeira do Drive.
//
// Versão resumível, mesmo padrão do LimparDuplicatasPendentes_v2.gs:
// roda em lotes de até 4.5 min, seguro rodar de novo quantas vezes
// precisar até aparecer "CONCLUÍDO".
// ============================================================

var PARES_PARA_LIMPAR_FINAL = [
  { origemId: '1tqATNJo8sB8K9HWE5USYzm-ehmx6HnFE', manter: '10Aa1zXybr5CMN28a36QL9pvt8OynXdHb', trashar: '1G9Aru7qtHwaXdURs7oLi0Wpa3rv6smFc' },
  { origemId: '1X4Jgcc4YHtoArB2uAIK6LoC583uTpB-q', manter: '1krnNlNrmX2GVpcwQ_fUsOipi1m6oWnu7', trashar: '1PwjESNmlpgAKKx5KnuWM5JaRek_2du51' },
  { origemId: '1KOrFAYriw0izgeo0V06ivhoW8kgyM3V8', manter: '1CcjLSKeJq31hqIZtgkM7-afiNaIU6BhL', trashar: '1n33i46QdzkTsmHNtpEEKgcQj9aGNnFwM' },
  { origemId: '1OLIGq64O3beZ_zR_rFwQvWohaDYJkouy', manter: '1MXyI6ECnzMW4l4hNjAtJEqgCJ0YrUbXb', trashar: '1h9aBMKJkNFPZnZH54TklzPbZEqybH760' },
  { origemId: '1bPYHcbq71L126e87ffFql6QJ_OQZVvPJ', manter: '1lF510nL0hmI3W-pMXmdDYj7MQ2Wfe0ni', trashar: '1JR8YoxUcOVXYyCm9XgVJXMs14KGa5gXT' },
  { origemId: '1nHqycSNPWUsc3d_AmFaJs2scVGyUfLwj', manter: '1hirW80R_HEVckBvmc-gF3U6UyLt-Lslz', trashar: '1Qgi95VDVbwPAjrM0ffsRDjUPDXFZ9l4q' },
  { origemId: '1YBcZ376ucDTGiug2zDZdt6ayzLmu6LxL', manter: '1uzRWKroaw-xxf3nEdDz9CWh_Sy30ZoCj', trashar: '1WRwrfSyiti3OYxmuR1IOhWH3LDmnpj3J' },
  { origemId: '1tGdTA-dB75gWG-Pbw2462bB000cn3o3C', manter: '1ImtKlUHIGiTts3e4A61bJwMNSWqmskts', trashar: '1Rj4NJLsW-PO-E1aSPZJd--DRtbHjoaxd' },
  { origemId: '1fYhjAwfL4QzFHvQvuUVwoqe7FMIvGbEV', manter: '1TpQm2eznHhXLM4K2fe6YtS2wnyyImr53', trashar: '1kvqK6vUmZ9c7PcF0Lekd3wI6irg_reYn' },
  { origemId: '13rTNs4mNXQV4Z6mF5H_8zN1CcaxcmdUp', manter: '14M1bY9ayYQP5LFxycLGFxIO_otQrKvpY', trashar: '1oytJmNeLDN5TJkvQCXvO2ucp7eKZ5AD7' },
  { origemId: '11S_0c42xWHuB7nk6-49iYCD6IcxYl0Hc', manter: '13iY2Hreh_Z-VU56eHZSVMqsA51Qq2s7B', trashar: '1iNVklWn9pNer21V3nRIfd1dKBpkAOVnx' },
  { origemId: '1qDrDRuyy5oP8Sgbfc6PBaFzMudK_uTH4', manter: '1eUH2sjyg_JdH6Td1etiVsFlrAhmVfuQN', trashar: '1zl3eut0Ve9r19iJMdvqyoPQJSeugHIb1' },
  { origemId: '1P7zkBKemyKyEgHCnY8JeNaD9GzuuZyx9', manter: '1FE_qN_Mws1cNRfu4KWoXmUjRxAyDacH4', trashar: '16xaAlVlh-C1L710JNAamuFnn7jlm50fy' },
  { origemId: '1abtnAzVmi7c4ih2bsYkd-jLpYov4LBft', manter: '1nqgkKSF79s4-PFtXMPDELA9z1Bksi1V_', trashar: '1PpHNkYocnQa5LxkbZRFVlMQbk9jmy7pS' },
  { origemId: '1Mz9eQux1pXqXKY4a5hafFc-zS5OUVyiv', manter: '1aq_VMXolvyAsKAZxpgdcZRyRhNkBRMs3', trashar: '10895c7cM4LaWsAHYLtgYpRLA2gl1-nvD' },
  { origemId: '1bbJ4-p3kF74_GXMsF2qih--9Em-iL1tO', manter: '10p92gqZ1ELZpgkHsunI_5QotCYFUfP75', trashar: '1MfcjQd17tex0soDFQezMFsGowDxfaCBc' },
  { origemId: '1tIPVhJmsA8r-3tJPsmonfrikoMJ8J7Zz', manter: '1b8HfDn9GSTYJGJ0F1jCPlse70hLyKPx3', trashar: '1mPKwUyv_ksyFRwmpEKT3CaEjcRduZgwE' },
  { origemId: '1PbND6yPKy4b_tY7DCgwOVvIvD1LCGVDB', manter: '1JuADpG_vhGYJFed13mCoHB8g4dPmxbS3', trashar: '1QyB2mrch79cEZIKdjwJEfrLec_9mkczf' },
  { origemId: '1rVv0aXZPPj4c_TKTCIPfGBapkk1_DunL', manter: '1tcFWnvgd5qhlpafLX5Xg5OkqHeixSS0E', trashar: '1_tRbl7klyG_9U6Q5h75dVrYmIR5UKbww' },
  { origemId: '1c_v5YwtG6UhDQufLZSOfnBCUXhb4hBLk', manter: '11rEjNo2cocmfCAjB_Kj3gpQTFdSK1tAq', trashar: '1yHIOhlS8Cmvz24FPV26BPEe6xqosfjzX' },
  { origemId: '1BrdKgOVbkajMsTC18utfTP18KJHOQ4WM', manter: '1mBtf88UdbCE_YbjNvWaYrd5XhLigDA9M', trashar: '1PIkKfUkt4sR2ly_2WdrD8uvBUVi_S3nE' },
  { origemId: '1xL1xD-DYGi5Wi9y_J_nxIGYIs3Q_zGiS', manter: '1JlnvbKpKutMpcZQr-M4WDuFEvgIcMkJj', trashar: '1VzDStDLaC4WYCFWeXCaqJGdkzOx3N_SP' },
  { origemId: '1hpLeRwOqAxo9zcW7jf7P2N4a1d2IdJHD', manter: '1pPBR3rh43zakjf0Ge_JLBY7ciXoje2AP', trashar: '1Atdo2YJMDfkttqXNCMw9NCtZTYusgncg' },
  { origemId: '1fnq1bPQntKERtIi7SCC2sjqFoasCZw6a', manter: '132E6cjoP0cI4nj21TSv8QitzmLeM4UaJ', trashar: '14sIRB_HTpr7MgUMPE4fRLUH4RgdMeD9n' },
  { origemId: '1iy-FQCsGpkaQ8jbX8OM_s-3gfAUCfX6z', manter: '1WuFRnoolBmaqz5LVql91awThdP96Qz_7', trashar: '1sbV8j5OB-Wq-Srm4N89pksat9aduS8ZD' },
  { origemId: '1UYux-arJ71HJuJfNYiJwYolenFdvOjfU', manter: '1xok7NsWz6fLb-W0ql2PMR9d6rILAon0r', trashar: '1_2u5BK65vYqJUSsW_JT-pyghYn5ERHJC' },
  { origemId: '1ZZzbvKLtg8KmxP1oqQR8_1kUmF2sjfsa', manter: '1UHVG8y4u0EXQ2tdBvUDLwuxwnhWP5k34', trashar: '1RQf2NMCgqww3BkXSoKJhVYQisFNA8EZy' },
  { origemId: '1I0nak4XTqAoSehXrMIm6tCbtaaR9bGUj', manter: '1F0Ge8WCYysUAmjsCnC29s9_yDZGhbmF_', trashar: '1tbUp-ww_TYs_iQBxrac7adMklwvSquSD' },
  { origemId: '18B-_inhmBknkxC-OSEIVU-cAfWrROGvs', manter: '1ks94tU2QsuOwHXUt0xp9IUWaWBNEspqC', trashar: '1XxZt56W7gLgPsPR7xHbdV4d6ntZBVfow' },
  { origemId: '1rE_s26yalMzgjOfgG06b3ZFOrWL3Alwx', manter: '1S7rzvO3ZnjEN_anZN2U7ONWzyKeD2INf', trashar: '1tJhsZx9Tn68s0ZeC0EGJB2IgAE1QHJuv' },
  { origemId: '1VY40AnfiEU4wHkR-QZlyqtVmni75jd9A', manter: '1lnUA3EsKSRmk99qXlY8PkTcbn7lyPtR5', trashar: '13lauzv4cdlTdlxdrpstqVxWTwLSU84GS' },
  { origemId: '1nUcNDu_Szh5xvTnWgdbs17ZUvfOo9IfT', manter: '1zZCbWCYSrcOZgvoKWkIp9JJh4aixocS-', trashar: '1e-4nv8gH50a695O7pPB2H_eEEKpnc83i' },
  { origemId: '1soHYjUSKbuiwOWhfloeE04hcnb_btJMD', manter: '1gR4MQvCDh9lnmzeQC7ZiaQ9HNn6dWeVK', trashar: '1vjd4u5KIUwNlTiGxqOyiMgo_WgQPfDB0' },
  { origemId: '1A_qjsdmbfrgjXs-icUNgg3GMYMLYO-zw', manter: '19IMG2yQQkRv1I4SxS8vLoE9l_aXOy0rt', trashar: '1yRlAVTzWIizq73HPLjF-m5BYrGj7EIzg' },
  { origemId: '1ez8-XFhQYq8FUw52K9hh2OLzJxWSJZhQ', manter: '11qKUdRyVxrJFne_nTcubTWUzUSoC3Z3v', trashar: '14eYJQ4LqeDCryr8V9BibBxBAL35bXO9J' },
  { origemId: '19Wn3qLzqWkjMAWgLHo39DuA5Y7AqD8Qo', manter: '1cuoj_WXpfvTDlKZyrJjmpyPgR_lV8QKv', trashar: '1OqebazWoyuSDoHCbKrzJbdJFt66OUmiH' },
  { origemId: '1YIdakjxe8C1VGdW6QJAw-vOcKxBoVtxq', manter: '1QvAmJkvURfgZasibaYkdw0r9fWW7Okqn', trashar: '1HQtxNMHHniTwO5_UODInalBcnahE7-uU' },
  { origemId: '1szFhL_HPfbxz6R-JH_f4PvQ-oVKnwCDH', manter: '1DRIRPMvVAR9BOpN8R1qJi5VR60LvuLZX', trashar: '1LlwZ7nphteoxns0MDfq1sRzZmiMHXOfE' },
  { origemId: '1ZDbiormY1jjX_0TvRdQxokXoS6fKqgtn', manter: '12yX0Zn7MKl-6uLIUWCfUO0OzTEBQWmiu', trashar: '1RrmKtlgkJAF2fsh_4YsrhzX7vpveLECU' },
  { origemId: '1LC0KrWntds3p-6PnzLccJS8Fr4nWvLKY', manter: '1VytOMcgQw8NGJ0EzG3uvQ6Q5SOb59Wvb', trashar: '1xDxTaHoA-ipyxJSFEHK6rqYz1rgiTC_T' },
  { origemId: '1jPjLZtctQ_YRXD2PE_vjrBepXnOkOXWX', manter: '1NC0FJ5p8L3mKmTMfYMCm24TvAWpJ0XmO', trashar: '1-h2XtfO70aoYRKLJpC5T3RohyUNAhjON' },
  { origemId: '1ZHmtK6BXDTPSj9-cUJzEJQI0kXAKL4ua', manter: '1d0kMV2FlpnohUTW3um9mGz4T7xyjCe85', trashar: '1FOo7bXM5XyeEioHesT0cueCNi7cstABZ' },
  { origemId: '1w5LIQ9yh-Yq1gIXvYm_Yn8PzbYQlqX_K', manter: '1Yx4wa5U5Mz_VbqxfIWNl2i3hsTbr-pF_', trashar: '1H1xMllupEZv_Amu_SLQL8BdAkI-J5ncc' },
  { origemId: '1gKG9-70yQBdZhiXpPq855Sm8qlFPi0P6', manter: '1p-IoWDrfD3KbOvadftlBtC-p-IMxfFCF', trashar: '1iLErF84wMGJ_KLUl3Apuyv4mtbDxhwlE' },
  { origemId: '1PhipZx_9YvkQwIle_JhMNic7vz2M3OFq', manter: '1xqcb33OleTkvycFh45QFMh0PToXO-mx7', trashar: '1jzDMji8cGePVwFoXVTqEtJgV3ygNYhlE' },
  { origemId: '1D8F3xQNS9ud6fFH_78UX_LmoMxo4qQ8m', manter: '1TvPRco6ImjIhf0idMp2mHkXXNMbyzRcJ', trashar: '1Yks3UfUGvcUu-OPPJ4wjertW0qrxnqkf' },
  { origemId: '1WnuuuTe-lVgh2NJEFrLjrmh1Ruf_5bFY', manter: '1FCT_vAOdindv9dUMaa6IMPl_1WWFThEa', trashar: '1oyAxF3Dft69MZc0_1xxgm344OBUGWgIM' },
  { origemId: '1bCMfS_KiAhAOWjoRkeEOfcdkruH4Ne5j', manter: '1O_iCDRMPCdDw1qyLcRvIfXsjW6KoAmcB', trashar: '1CfxaFaoXdQzkvuHdRYjnmFMwlX6xFQ3W' },
  { origemId: '1O3O5T3ZDgyRJrur5QU7-ognM8NrfDs_X', manter: '1FOz8RmE0lVVSUp6prmqAJel1qzFOEXBg', trashar: '1kgg4A3BsjDBf-O7G0ATQKHKQWhD7Q-3d' },
  { origemId: '1F5FX9LjC3N1QnSPEKqDZ09TbPFhNKedl', manter: '1cwzRsg4Spdn0ZyDTSunsg7mZ7o20-Plv', trashar: '1R2aFX-Rw5biFR5dhDrhOw8vZD5xrCnlf' },
  { origemId: '1l0oAM15N-W2fVB2RFuXFFc7OEQGAm6Hz', manter: '13NssAg47-tVXK1SdQCzIJyuOcSgFfoMI', trashar: '1nft0Kl9wR9VlGKiXUMXayoYhU9A2iykG' },
  { origemId: '1RaIUvVA6amOFETCTKI-QnUC2ttAbHuIj', manter: '1j81alxdOz4-7dmnUN6J0lZtxjGHTTGng', trashar: '12b0KiK9uBrOYTlTKufkCO85-_ojI8sEP' },
  { origemId: '1NWonmsN6LetCHal88lhHamwjngKji2Mm', manter: '14vy-exh2xQte3r_clP0aYmnQtMHTVi9L', trashar: '1bCO8S9HkePmrQYv55kvgWO-_R8PhJ34i' },
  { origemId: '16X4Lv2KAdTELmuhDF7Ip0QPy8vtGtCus', manter: '16hywawB8w5E8FZPRPGxLiCYZFgsagWfx', trashar: '1oDx-WaQaiWQiyoySpHLpSgoJy7KtXc1B' },
  { origemId: '1GEMAI7uRKT8gL7erjzwWt1UnwFy2PiT6', manter: '1qaIig_XarKeHa6O9MBTlCqmsQa6xopxJ', trashar: '1trGI1kdGcFnIY_KQl4AJ2xjaoDN9c4_u' },
  { origemId: '1mcpw_66YTGj9FYLFUKizTm-1NfN7cPpx', manter: '12Q4QDlPPR_UcFpxiwHXGe8eQvDlyU1_G', trashar: '19Ei3b9qDqdv8H6p6L7QsUnuD8ZdjRF5J' },
  { origemId: '15tweB_UWIIlQ_QFVpRvx4HKidw9sr7NL', manter: '1nDbA2wSmXes_WQu77SCMXca_dRzlWME_', trashar: '19iaXFSbfyyu1jOmvJYicSGfhQXBHjrut' },
  { origemId: '1MOcEOd1e3lWmj6YpsCguFrs9WAPc0cSv', manter: '1BBUfJmkmz-5YG59NXQMEWC_IgqQcPfkx', trashar: '1RazdxGNFOuLFA2B-chMnd7svtt9B99_m' },
  { origemId: '1Mx_GjYPsLWj8GV5OAf6JP9EKhZqbUsag', manter: '1_xoaoYLF7tJ3ADWRPcbg4UfvXtvt5jC0', trashar: '1aqEXCgNKKY0Q8tWp_L4wI4FxxK1vqK6g' },
  { origemId: '1yQvjGUV31G2sd3C3JZJHhUTpJO1JU4Ic', manter: '18PaL9NZuuuq93Sx8O5F3nxw5MlD2EdIj', trashar: '1sRYTSWI4dO3R26tKz-3U7YTDAmStl3bN' },
  { origemId: '1QycMhbgonkj0UNzQNEIEjI2G5ObdcDQA', manter: '1JEf3Era6CGI5G4IZamrBCA3DkHd800CL', trashar: '1ES_4wYeFymKyP6QiHb7R628PFWs90tR-' },
  { origemId: '1bM95-L796K2u6SscwV4uj-M6HdhYzbCB', manter: '1HxkDV4SXi9owELXKrKBOLJ8b3QkGjEin', trashar: '1DSM31HUsJe7BJxKrV67n6bk9e_VC3wJd' },
  { origemId: '1cT-2Zr0v3xSX9PdGbFe7tm2QYm7La88x', manter: '1fiOK54AwtFlTbWWC5G-bOLozMpgdvTsq', trashar: '1rL26zXGamJOin2P5rWYIP8gKkREXJMuV' },
  { origemId: '1ezjC86hVzlVdIzRKl2xEQPelYz6fkpN1', manter: '1ZuYYRm_Au_gqii2j1jTtOGnaGDE3Wbzc', trashar: '1abpcAl99tjRKkd96FomleJ8bKkgAlik1' },
  { origemId: '12QtBSJIampLx3VwM5IiFSCVUA3y36NUD', manter: '1YSw2sVZYN4oPtq4sfuSU59lwhYP5FNxb', trashar: '1HOc7SsoXvD0x1fsvZmmx8tNQesaD_bFK' },
  { origemId: '1pxRt51VLyxsknYshRoQCiO86oVNH4BFH', manter: '1e9dK0VCIejuV6uwAYCabrc_U52Wmg23s', trashar: '1getxInV8Ghne8vnZuq2WtH15X2yUGcmk' },
  { origemId: '1jjEvMYizGqf_RlxcvDEBKG53u5MdcnRv', manter: '1yYm1k-0ZDXT7rqS2NPyU61raNFNrRRiY', trashar: '1_udngQZWG9oOpjP_pm7vUoP7KryTKELe' },
  { origemId: '1q9ehivlAMMoRid81C9UMrdeQpLkNMgOs', manter: '1ie8tHrNepU18QD97DEsenXvUyvCbSDiz', trashar: '1kto8mTtn1lnPA4v4QzCQchtzwS5uqiHB' },
  { origemId: '1mfU9UmLA0e5Fou4MQhTMw5ioGOhPKiA1', manter: '1O2iLOOc7LoBEHIWYxZ7IbYaKkneR2jrq', trashar: '19UkGGr65JA9I8KBBExN9bHyqrVrrRPGg' },
  { origemId: '1nJAetcB4fc7VHg2UpWtk18LZOAK25V2H', manter: '18wbSDTzgcyMxvcwObZEBrSLwNjqMK3mU', trashar: '1M-s0DZ6_ZGnwB9iapQyY79dq-MZ9-wdX' },
  { origemId: '10cQiJlbG6ZbJKvZcicqs4VjXIHU-cGJh', manter: '1BB__sn5cwGEZaHBV82R7FZgP728Fxd1i', trashar: '1HCPV8U72I8Ttfuj3kZHLGeap9PENctNt' },
  { origemId: '1a-xrz5fUWdD8Qqk6srTdz2XpHc3hYFcu', manter: '1I5s1Ga6v6w3fbrciNXXoYceOOBewbqpY', trashar: '1Z7Zrdnv5OjDxxegF8yZr9x4K0bmIKFV6' },
  { origemId: '1TSbHQp_MJZ7LBus9dbr9e_9OxRXY5UA8', manter: '1JIfCPlhtvVxjGxlaKmjDSKRJerhBMf5F', trashar: '18hEkl9gi4A2tNrYdOnfGKu7LW_uP_8IT' },
  { origemId: '1dEZyH11XuUHkIZH5GaoZw5fzRf25itOO', manter: '1Vk3hOBSDIjnN2rHFOKr1liFy7HQMKOIo', trashar: '15chVK7b9a77WY6GESmd_ynJ5EqirsMGm' },
  { origemId: '1eBQkIn-eBxIo9MrpLuhTooBY_25sSZnr', manter: '1u0jMzucDB7UzKFgGFZK3ykNDLXTayX_2', trashar: '10JgBpBmJb1OYuqXq0gq2I1QtGLiJz_lz' },
  { origemId: '1SCE4i-K4tVmJsoBRZ8JlQrP5D9I6K76V', manter: '1f2Q7_HxnhUaQ7EHrnVecaSyP5gGyIwfw', trashar: '1eNzBihDw4nQhokw1iODYkJTVXu6N-cJj' },
  { origemId: '15uY06WwpurrVweFP2xg_MEe0_bX1Z8Vf', manter: '1cF0fM8fpVfemnfM-71SjiIZ3eOxkn4Ie', trashar: '1Pi2UJuPrB0IzPEkxWV10o01qrYHw5RzH' },
  { origemId: '15qXY5rgdWzLfvzCK0dNonyZKzWnqrT78', manter: '1ebEQL-LDreaMT1_Gi17xsbHdpOuUFxC2', trashar: '1dbz5TXrGI30Li0kCMZemgCBWOrQWJAsv' },
  { origemId: '1aqPs71SqRxi4LNu3qR_AbMFdMdcH_O8j', manter: '1jlGrjIzGaBfb04boETBtcHR8nFKS_rAQ', trashar: '1pRh3axMjnBy-zjEIhTYZdiqtMZ1I0E0V' },
  { origemId: '1TCGrvkLNhAyJfxYiwtiGFoIaVLot08IZ', manter: '1uZO8Rpbt402UZb4Fa9g_KTWaBazrfIEj', trashar: '1znhs1AQ_A2-PocUc_42KKsl-0tWq_SFE' },
  { origemId: '1pbe1ykcZcXxzWrWmHKHU8XuBQBl03l6I', manter: '1gwEl0N4w1jFSvaT8x3sbfTtEKieN-UvM', trashar: '1LhooNsTbI79PdMV501Qzbv-Q8dMAQZef' },
  { origemId: '1s0Hef7fAln9K8TAFWmUiD_zIiufKz6NY', manter: '1taV9iluIX62MZ_XpEO9qJJmTFzp5dZPy', trashar: '1x3aV_kHU9UkYaw9uSn4D8YMnS_flxlLX' },
  { origemId: '1uqAX9kDj3VggFGhfgszaQQYgv4aj2ro2', manter: '1a0yNmpdriJb6Ve0xk9KJ-Pcb0IK96PdJ', trashar: '16RGdVQJTusvVcBeyDJa4boln7O3ndhLW' },
  { origemId: '1jfDiz3Xl1maazlOL6kI5vhTmKBYsM9l3', manter: '1uyEIf4Pr66oyCxV_TTNPBZn_hANmWHKY', trashar: '1kUCqIxFMRf1b2nvJH4AnVUa60Uvo6kpv' },
  { origemId: '1Pc7UZKpkdX5sQ81T7d__Ca9h_7RwKY4D', manter: '1LrqA4iwNJSKAR0fGvOe5Rr_MMg7ohtvQ', trashar: '15zvksnf1sH6nyuMqM5DLB1MQ931wEDuW' },
  { origemId: '1YV6_U6isnIg3eEd9HeqysT_-HuDq9jIa', manter: '17EH57It3HlBrVpGo3mfXvDEG01blkNa2', trashar: '13QjJ4VqLcyTketnTyGYmhHndCwZQO9Sz' },
  { origemId: '1tWDybCxR57t4a0y14z80GmpVPDWUrAFg', manter: '1GRpZWvJsuG3w4fExMoYOBHm8L1nrJNwV', trashar: '1XeIJHmocrJaqq-J-bzudgZl6t3yPHW2y' },
  { origemId: '1N6k0a7xzlOZZFxE_vRlh0lsm4HV2GPhO', manter: '1UTTUFdhg321309I6RPodzF-hJpB28kH5', trashar: '1--45Qt-C0f2gxP_zrTvkaoSV9j3hQtHb' },
  { origemId: '1iTOaaNUfpyJq50l3VHGaEYfeIAI4K9zm', manter: '1nTuBBZwAB2ZZzabhxG55Glxa5RKNQ_oF', trashar: '1bUyf97qE4rx38P30aXUOtU3a6oLEJprq' },
  { origemId: '1yDMbrW5PhO4FtCq5TSwEByIzA-LVK5Jw', manter: '1ow50otwCDsWXqbJMV3o88r_WOiA9idhg', trashar: '1EOesOq9s3sCEc3cYGqKzGGkKByxig302' },
  { origemId: '136yBXvxrIhqH_dp0qqXLa8qjictBhi2L', manter: '13IhofqHDCgrjRvEfzu6CjvdKcmOrjc-z', trashar: '1EQzkcvVg3D_vKNFfuMjwEhdAnV-UsAdC' },
  { origemId: '1RH98sLTvNwgBHLGjjSbqTaczBrGlAIbb', manter: '1iaDFZ__v4nlFrg5KBLKML_iCmVQnAkq8', trashar: '1clcafChovrHtePDUfHfnbLwi1Hs9bAp6' },
  { origemId: '1SFajcGcarS6Kdp6WLZJkeSD0B64jiNoV', manter: '1dR83Z42Rcn_CzWXJywWZ-0a1yxM4aMzA', trashar: '1kc9fUeCdcKFG02tJ4yRJisGYz9QzY-JT' },
  { origemId: '129WslWtEcnGpEWrWBP027EQh4TPfpw9j', manter: '1LceuFscaH4UznJ1a8RtChgux6pZ21TRK', trashar: '15MhEmY-a3jchkvCLNd-hS8CvbncxRNva' },
  { origemId: '1k6CfrgCjGi8jfoEHkQxSROivnm0PsPxF', manter: '1lGq6vl-cMkFVoeQYRG8YjMjW0IH-HJKv', trashar: '1CviQk6OCly_YZeGyv37bqxfCbO_6w35c' },
  { origemId: '1xq1-xyiHCPUzB3ZByMyyEBQO9gCK-dS1', manter: '1n6W1T2sZ7kAITqoD5w30QDHtL9i3W_Kp', trashar: '1P3LJNgl34l25dk5ktUhvoAps-FbLDdNh' },
  { origemId: '1QstRl-73coatL7josrs0xo63SZEJGPee', manter: '1utNygsoGaDLkHyC1KkHQLmOz-W-3CaHj', trashar: '1avHiAbFNM-BqTf2jF7fGEUFQGUH37N2d' },
  { origemId: '1EayK6Pn4URKvcYvI6aP8KqqZZuzkVDUO', manter: '1FngzhCORdF5Y_G867o0Zq467orC3OWMy', trashar: '11m1s3Q-e-tfu2nUSuQJV8bXEI48wf9_U' },
  { origemId: '1TEOEWy5QpAtoHUgeC3gFz6MBQJ7rXJ15', manter: '18GFYc5xNSmizCsqFiE7IlHc7xMgQd81A', trashar: '1UtUdsP51R7J-e45iYnzEpeTEWzI_FIXW' },
  { origemId: '1uOZunqNA4iiztl-mOLHmltZLvq1S6u0j', manter: '1Uv5r0WpMNpQEP4xbfaYFFxWoS_W0VHZX', trashar: '19MBLgz_Cd2jHq7-aSjJdHPAZB0zPKl00' },
  { origemId: '1Co12SvNT-Epch4i5WvqVqYzvuX3ZT_P6', manter: '13tj-5YGpJG5eXJPtXvxb7PEIzA0u3duL', trashar: '1m_Q4h_MQjUg2IJsIbJCqUJcXhAUK3DBU' },
  { origemId: '1UCpw_ANFM2PskMJ46qF9FzEk5I7LRXKT', manter: '1xq0uYj1YyESuHD6-rXmTPNsRG-qCG6gA', trashar: '19cQC2RYseUXxsQddfrhYZCpb3JpZVNCT' },
  { origemId: '1KD4lRakFXt04G_nqNCI8c_cJokEQYFAm', manter: '1D1S-huMJy6e5OXNCYAuQdoHwGg716fOJ', trashar: '1mb2J2XA9L3D6FgQnsfjsXX9nRqdToGGB' },
  { origemId: '1yWU8q5oD8deRzCNuPaI__5wG00WnYaZe', manter: '1MnCCOcO9MEuT_AdCFhgTg_QaX4jVe7KE', trashar: '1veptVnraoIiA6SizxO-TG9Q5KEGgEJVV' },
  { origemId: '1QElPQ1aLuZQ-2KORxBtWoJ7m0DI9B_SN', manter: '1VHYd6mMI928vcmAOs7nkH46B6IE633d1', trashar: '1yLjk2TiaIF5U9VtB-os_GvOaYyvwWuc8' },
  { origemId: '1AhNqajQji1fAI7ykv5UQ3ReRRqSRs03g', manter: '1ZVZCvNzUXYZGlYXHkffYqLzl0gy13QMR', trashar: '1X3dauk33iNHQ3ffvNoemmUjO-ONGVZyJ' },
  { origemId: '1BF2SCTpMOFHD-ipYUuE_cKZ3O4E-F6y_', manter: '1l4O2t6bGxF7Of2mdPVf0QamD5iyVAg7A', trashar: '1u_KfsougCOPqQTot8dRFQK5f--AD7rv5' },
  { origemId: '1jWWPTAF7XTF6ohsKiPKqB9cxXPRZGKDj', manter: '1yKGroIirx7fZ8LQL1ihb_OKGU-0Fu1pW', trashar: '1sb0bqvYK2OsMljOuXBM8BH_Quo0V0yNJ' },
  { origemId: '1c3oexhL-jBdHY42_FKpTb9JY7V-PJwRn', manter: '1yTpo2y1-embHGL3HfHjuDCvNS0wlJMdB', trashar: '1Jgm4o63cjoU90YPjF5lATPF38UGb7lvQ' },
  { origemId: '1ELNXBGdeA1y6HvNXXKNxGoSh3nvEnDMX', manter: '1EVvkQLsC37uww1LnI0H1AaLH0kgazc4X', trashar: '1E2wfvuGqlthP6uWiPoH8uCv7zUqRQnTq' },
  { origemId: '1FhTnh9Mn1PAAcXEcLW4Z6rdI49KvgvmP', manter: '1EETjcMPVViCcmJoGVfXvGR1Hx2M4uv-G', trashar: '17Cgp9DmvShz5AqjL2AcCClx9cJMUlhJ2' },
  { origemId: '1Ge3vACX04caYJI44kRQ1N8IlCJuIhFeM', manter: '1ZwCQcHPJt2dV4AMTpUciRuu4aFncHT-Y', trashar: '1Ajv-bR2d-v3oTTPgKTuKMjdqCEmfCOJq' },
  { origemId: '1OcyeEB0B44GkYV-6nE3Z2wrbWaQlEGCC', manter: '1y415rFtImVZDGH4Y2IGCjfs0ZNrcwulE', trashar: '1LEzgzgrfeSV3MreuvC9igDuCkn3ZwnMf' },
  { origemId: '1Te-rb3i-zo2S_uMHdPVakcs5aRpplnXN', manter: '103z7D-zIoBxYd0HJGhvFbm_3w33EYP2m', trashar: '1Y6rnxLo6cn-NeTudxaFe4dsVsGrAQ0RW' },
];

function limparDuplicatasFinal() {
  const inicio = new Date().getTime();
  const LIMITE_MS = 4.5 * 60 * 1000;

  const props = PropertiesService.getScriptProperties();
  const planilhaId = props.getProperty('PLANILHA_ID');
  if (!planilhaId) { Logger.log('PLANILHA_ID não encontrado — rode isso no mesmo projeto do iniciarCopia().'); return; }

  const fila = SpreadsheetApp.openById(planilhaId).getSheetByName('Fila');
  const destinosParaTrashar = new Set(PARES_PARA_LIMPAR_FINAL.map(function (p) { return p.trashar; }));

  // 1) Remove da fila as linhas que apontam pro lado que vai ser descartado
  // (rodar de novo é seguro: linhas já removidas simplesmente não aparecem
  // mais nessa busca).
  const dados = fila.getDataRange().getValues();
  const linhasParaRemover = [];
  for (let i = 1; i < dados.length; i++) {
    if (destinosParaTrashar.has(dados[i][1])) {
      linhasParaRemover.push(i + 1);
    }
  }
  linhasParaRemover.sort(function (a, b) { return b - a; });

  let linhasRemovidas = 0;
  for (let i = 0; i < linhasParaRemover.length; i++) {
    fila.deleteRow(linhasParaRemover[i]);
    linhasRemovidas++;
    if (new Date().getTime() - inicio > LIMITE_MS) {
      Logger.log('⏸️ Tempo esgotado removendo linhas da fila (' + linhasRemovidas + '/' + linhasParaRemover.length + ' nessa passada). Clique em Executar de novo pra continuar.');
      return;
    }
  }
  if (linhasParaRemover.length > 0) {
    Logger.log('✅ Linhas removidas da fila nessa passada: ' + linhasRemovidas + '/' + linhasParaRemover.length);
  } else {
    Logger.log('✅ Nenhuma linha duplicada restante na fila (já foi limpo antes).');
  }

  // 2) Move as pastas descartadas pra lixeira (pula as que já estão trashed)
  const listaDestinos = Array.from(destinosParaTrashar);
  let trashadasAgora = 0, jaEstavam = 0, erros = 0;
  for (let i = 0; i < listaDestinos.length; i++) {
    try {
      const pasta = DriveApp.getFolderById(listaDestinos[i]);
      if (pasta.isTrashed()) {
        jaEstavam++;
      } else {
        pasta.setTrashed(true);
        trashadasAgora++;
      }
    } catch (e) {
      erros++;
    }

    if (new Date().getTime() - inicio > LIMITE_MS) {
      Logger.log('⏸️ Tempo esgotado movendo pastas pra lixeira (processadas ' + (i + 1) + '/' + listaDestinos.length + ' nessa passada, ' + trashadasAgora + ' novas, ' + jaEstavam + ' já estavam). Clique em Executar de novo pra continuar.');
      return;
    }
  }

  Logger.log('🎉 CONCLUÍDO! Pastas movidas pra lixeira nessa passada: ' + trashadasAgora +
             '. Já estavam na lixeira: ' + jaEstavam + '. Erros: ' + erros + '.');
}
